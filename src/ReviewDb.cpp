// Review Database: Implementation.
// License: GPL-2.0+

#include "ReviewDb.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QStandardPaths>
#include <QUuid>

// Construction / Destruction.

ReviewDb::ReviewDb(QObject *parent)
    : QObject(parent)
{
}

ReviewDb::~ReviewDb()
{
    close();
}

// Lifecycle.

QString ReviewDb::defaultDbPath() const
{
    QString dir = QStandardPaths::writableLocation(
        QStandardPaths::GenericConfigLocation);
    return dir + QStringLiteral("/linguaspanner/linguaspanner.db");
}

QString ReviewDb::makeConnectionName() const
{
    return QStringLiteral("reviewdb_%1")
        .arg(reinterpret_cast<quintptr>(this), 0, 16);
}

bool ReviewDb::init(const QString &dbPath)
{
    close();

    m_dbPath = dbPath.isEmpty() ? defaultDbPath() : dbPath;
    m_connectionName = makeConnectionName();

    QDir().mkpath(QFileInfo(m_dbPath).absolutePath());

    auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"),
                                        m_connectionName);
    db.setDatabaseName(m_dbPath);

    if (!db.open()) {
        qWarning("ReviewDb: failed to open DB: %s",
                 qPrintable(db.lastError().text()));
        return false;
    }

    // WAL mode + foreign keys
    QSqlQuery q(db);
    q.exec(QStringLiteral("PRAGMA journal_mode=WAL"));
    q.exec(QStringLiteral("PRAGMA foreign_keys=ON"));

    if (!ensureSchema()) {
        qWarning("ReviewDb: schema creation failed");
        close();
        return false;
    }

    // Load any saved FSRS parameters
    loadEngineParams();

    return true;
}

void ReviewDb::close()
{
    if (m_connectionName.isEmpty())
        return;

    if (QSqlDatabase::contains(m_connectionName)) {
        {
            QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
            if (db.isOpen())
                db.close();
        }
        QSqlDatabase::removeDatabase(m_connectionName);
    }
    m_connectionName.clear();
    m_dbPath.clear();
}

bool ReviewDb::isOpen() const
{
    if (m_connectionName.isEmpty())
        return false;
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    return db.isValid() && db.isOpen();
}

// Schema.

bool ReviewDb::ensureSchema()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    if (!db.isValid())
        return false;

    QSqlQuery q(db);

    // review_cards.
    q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS review_cards ("
        "  id                TEXT    PRIMARY KEY,"
        "  translation_id    TEXT    NOT NULL UNIQUE,"
        "  stability         REAL   NOT NULL DEFAULT 0.0,"
        "  difficulty        REAL   NOT NULL DEFAULT 0.0,"
        "  state             TEXT   NOT NULL DEFAULT 'new'"
        "                     CHECK(state IN ('new','learning','review','relearning')),"
        "  due               TEXT   NOT NULL"
        "                     DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')),"
        "  last_review_at    TEXT,"
        "  elapsed_days      INTEGER NOT NULL DEFAULT 0,"
        "  scheduled_days    INTEGER NOT NULL DEFAULT 0,"
        "  reps              INTEGER NOT NULL DEFAULT 0,"
        "  lapses            INTEGER NOT NULL DEFAULT 0,"
        "  created_at        TEXT   NOT NULL"
        "                     DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')),"
        "  updated_at        TEXT   NOT NULL"
        "                     DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now'))"
        ")"
    ));
    if (q.lastError().isValid()) {
        qWarning("ReviewDb: create review_cards: %s",
                 qPrintable(q.lastError().text()));
        return false;
    }

    // Indexes
    q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS idx_review_cards_due "
        "ON review_cards(due)"));
    q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS idx_review_cards_state "
        "ON review_cards(state)"));

    // review_log.
    q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS review_log ("
        "  id                    TEXT    PRIMARY KEY,"
        "  card_id               TEXT    NOT NULL"
        "                         REFERENCES review_cards(id) ON DELETE CASCADE,"
        "  rating                INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 4),"
        "  state_before          TEXT    NOT NULL,"
        "  elapsed_days          INTEGER NOT NULL DEFAULT 0,"
        "  stability_before      REAL   NOT NULL,"
        "  stability_after       REAL   NOT NULL,"
        "  difficulty_before     REAL   NOT NULL,"
        "  difficulty_after      REAL   NOT NULL,"
        "  retrievability_before REAL   NOT NULL DEFAULT 0.0,"
        "  scheduled_days        INTEGER NOT NULL DEFAULT 0,"
        "  reviewed_at           TEXT"
        ")"
    ));
    if (q.lastError().isValid()) {
        qWarning("ReviewDb: create review_log: %s",
                 qPrintable(q.lastError().text()));
        return false;
    }

    q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS idx_review_log_card "
        "ON review_log(card_id)"));
    q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS idx_review_log_reviewed_at "
        "ON review_log(reviewed_at)"));

    // fsrs_params (singleton row).
    q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS fsrs_params ("
        "  id                INTEGER PRIMARY KEY CHECK(id = 1),"
        "  w                 TEXT   NOT NULL"
        "                    DEFAULT '[0.212,1.2931,2.3065,8.2956,6.4133,"
        "0.8334,3.0194,0.001,1.8722,0.1666,0.796,1.4835,0.0614,0.2629,"
        "1.6483,0.6014,1.8729,0.5425,0.0912,0.0658,0.1542]',"
        "  desired_retention  REAL   NOT NULL DEFAULT 0.9,"
        "  max_interval       INTEGER NOT NULL DEFAULT 36500,"
        "  enable_fuzzing     INTEGER NOT NULL DEFAULT 1,"
        "  created_at         TEXT   NOT NULL"
        "                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')),"
        "  updated_at         TEXT   NOT NULL"
        "                    DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now'))"
        ")"
    ));
    if (q.lastError().isValid()) {
        qWarning("ReviewDb: create fsrs_params: %s",
                 qPrintable(q.lastError().text()));
        return false;
    }

    // Insert the singleton row if it doesn't exist yet
    q.exec(QStringLiteral(
        "INSERT OR IGNORE INTO fsrs_params(id) VALUES(1)"));

    migrateSchema();

    return true;
}

void ReviewDb::migrateSchema()
{
    // Future migrations go here.
    // Pattern:
    //   1. PRAGMA table_info(table) to check column existence
    //   2. ALTER TABLE ADD COLUMN if missing
}

// FSRS parameters.

void ReviewDb::loadEngineParams()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    if (!db.isValid())
        return;

    QSqlQuery q(db);
    q.exec(QStringLiteral(
        "SELECT w, desired_retention, max_interval, enable_fuzzing "
        "FROM fsrs_params WHERE id = 1"));

    if (!q.next())
        return; // use engine defaults

    auto p = m_engine.parameters();

    // Parse w array
    QJsonArray wArr = QJsonDocument::fromJson(
        q.value(0).toString().toUtf8()).array();
    if (wArr.size() == 21) {
        for (int i = 0; i < 21; ++i)
            p.w[i] = wArr[i].toDouble();
    }

    p.desired_retention = q.value(1).toDouble();
    p.max_interval = q.value(2).toInt();
    // enable_fuzzing at q.value(3) — used in scheduling layer

    m_engine.setParameters(p);
}

QString ReviewDb::loadFsrsParams()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);

    QSqlQuery q(db);
    q.exec(QStringLiteral(
        "SELECT w, desired_retention, max_interval, enable_fuzzing, "
        "       created_at, updated_at "
        "FROM fsrs_params WHERE id = 1"));

    if (!q.next())
        return QString();

    QJsonObject obj;
    obj[QStringLiteral("w")] = QJsonDocument::fromJson(
        q.value(0).toString().toUtf8()).array();
    obj[QStringLiteral("desired_retention")] = q.value(1).toDouble();
    obj[QStringLiteral("max_interval")] = q.value(2).toInt();
    obj[QStringLiteral("enable_fuzzing")] = q.value(3).toInt();
    obj[QStringLiteral("created_at")] = q.value(4).toString();
    obj[QStringLiteral("updated_at")] = q.value(5).toString();

    return QString::fromUtf8(
        QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

bool ReviewDb::saveFsrsParams(const QString &json)
{
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject())
        return false;
    QJsonObject obj = doc.object();

    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "UPDATE fsrs_params SET "
        "  w = ?, desired_retention = ?, max_interval = ?, "
        "  enable_fuzzing = ?, "
        "  updated_at = strftime('%Y-%m-%dT%H:%M:%S','now') "
        "WHERE id = 1"));

    // Serialize w array back to JSON text
    QJsonArray wArr = obj.value(QStringLiteral("w")).toArray();
    if (wArr.size() == 21) {
        q.bindValue(0, QString::fromUtf8(
            QJsonDocument(wArr).toJson(QJsonDocument::Compact)));
    } else {
        // Keep current w
        QSqlQuery qw(db);
        qw.exec(QStringLiteral("SELECT w FROM fsrs_params WHERE id = 1"));
        if (qw.next())
            q.bindValue(0, qw.value(0).toString());
        else
            q.bindValue(0, QVariant());
    }

    q.bindValue(1, obj.value(QStringLiteral("desired_retention"))
                    .toDouble(0.9));
    q.bindValue(2, obj.value(QStringLiteral("max_interval"))
                    .toInt(36500));
    q.bindValue(3, obj.value(QStringLiteral("enable_fuzzing"))
                    .toInt(1));

    if (!q.exec()) {
        qWarning("ReviewDb: saveFsrsParams: %s",
                 qPrintable(q.lastError().text()));
        return false;
    }

    // Reload into engine
    loadEngineParams();
    return true;
}

// Card creation.

QString ReviewDb::createCard(const QString &translationId)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    if (!db.isValid())
        return {};

    // Check if card already exists
    QSqlQuery qc(db);
    qc.prepare(QStringLiteral(
        "SELECT id FROM review_cards WHERE translation_id = ?"));
    qc.bindValue(0, translationId);
    if (qc.exec() && qc.next())
        return {}; // already exists

    const QString cardId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "INSERT INTO review_cards (id, translation_id) VALUES (?, ?)"));
    q.bindValue(0, cardId);
    q.bindValue(1, translationId);

    if (!q.exec()) {
        qWarning("ReviewDb: createCard: %s",
                 qPrintable(q.lastError().text()));
        return {};
    }

    return cardId;
}

// Review submission.

QString ReviewDb::reviewCard(const QString &cardId, int rating)
{
    if (rating < 1 || rating > 4) {
        qWarning("ReviewDb: reviewCard: invalid rating %d", rating);
        return {};
    }

    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    if (!db.isValid())
        return {};

    // 1. Load current card state.
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT stability, difficulty, state, reps, lapses, "
        "       last_review_at, scheduled_days "
        "FROM review_cards WHERE id = ?"));
    q.bindValue(0, cardId);
    if (!q.exec() || !q.next()) {
        qWarning("ReviewDb: reviewCard: card %s not found",
                 qPrintable(cardId));
        return {};
    }

    FsrsEngine::MemoryState current;
    current.stability = q.value(0).toDouble();
    current.difficulty = q.value(1).toDouble();
    QString stateStr = q.value(2).toString();
    int reps = q.value(3).toInt();
    int lapses = q.value(4).toInt();

    // 2. Calculate elapsed days.
    double elapsed_days = 0.0;
    QDateTime lastReviewAt;
    if (!q.value(5).isNull()) {
        lastReviewAt = QDateTime::fromString(q.value(5).toString(),
                                              Qt::ISODate);
        elapsed_days = lastReviewAt.daysTo(QDateTime::currentDateTimeUtc());
        if (elapsed_days < 0.0)
            elapsed_days = 0.0;
    }

    int scheduled_days = q.value(6).toInt();

    // 3. Run FSRS algorithm.
    bool isFirstReview = (current.stability <= 0.0);

    FsrsEngine::ReviewResult result;
    if (isFirstReview) {
        auto ms = m_engine.initMemory(rating);
        result.memory = ms;
        result.log.memory_before = {};
        result.log.memory_after = ms;
        result.log.rating = rating;
        result.log.elapsed_days = 0.0;
        result.log.retrievability = 0.0;
        result.log.scheduled_days = m_engine.getInterval(ms.stability);
    } else {
        result = m_engine.review(current, rating, elapsed_days);
    }

    // 4. Update counters.
    int newReps = reps + (rating >= 2 ? 1 : 0); // Hard/Good/Easy = success
    int newLapses = lapses + (rating == 1 ? 1 : 0); // Again = lapse

    // 5. Determine new state.
    QString newState = stateStr;
    if (isFirstReview) {
        newState = QStringLiteral("learning");
    } else if (rating == 1) {
        newState = QStringLiteral("relearning");
    } else if (stateStr == QStringLiteral("learning")
               && result.memory.stability >= 1.0) {
        // Graduation: after a successful learning review, promote to review
        // if stability is at least 1 day
        newState = QStringLiteral("review");
    }

    // 6. Update the card.
    QString nextDue = QDateTime::currentDateTimeUtc()
                          .addDays(static_cast<int>(
                              std::ceil(result.log.scheduled_days)))
                          .toString(Qt::ISODate);

    QSqlQuery up(db);
    up.prepare(QStringLiteral(
        "UPDATE review_cards SET "
        "  stability = ?, difficulty = ?, state = ?, "
        "  due = ?,"
        "  last_review_at = strftime('%Y-%m-%dT%H:%M:%S','now'),"
        "  elapsed_days = ?, scheduled_days = ?,"
        "  reps = ?, lapses = ?,"
        "  updated_at = strftime('%Y-%m-%dT%H:%M:%S','now') "
        "WHERE id = ?"));
    up.bindValue(0, result.memory.stability);
    up.bindValue(1, result.memory.difficulty);
    up.bindValue(2, newState);
    up.bindValue(3, nextDue);
    up.bindValue(4, static_cast<int>(elapsed_days));
    up.bindValue(5, static_cast<int>(result.log.scheduled_days));
    up.bindValue(6, newReps);
    up.bindValue(7, newLapses);
    up.bindValue(8, cardId);

    if (!up.exec()) {
        qWarning("ReviewDb: reviewCard: update failed: %s",
                 qPrintable(up.lastError().text()));
        return {};
    }

    // 7. Insert review_log entry.
    const QString logId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QSqlQuery log(db);
    log.prepare(QStringLiteral(
        "INSERT INTO review_log ("
        "  id, card_id, rating, state_before, elapsed_days,"
        "  stability_before, stability_after,"
        "  difficulty_before, difficulty_after,"
        "  retrievability_before, scheduled_days, reviewed_at"
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));

    log.bindValue(0, logId);
    log.bindValue(1, cardId);
    log.bindValue(2, rating);
    log.bindValue(3, stateStr);
    log.bindValue(4, static_cast<int>(elapsed_days));
    log.bindValue(5, result.log.memory_before.stability);
    log.bindValue(6, result.log.memory_after.stability);
    log.bindValue(7, result.log.memory_before.difficulty);
    log.bindValue(8, result.log.memory_after.difficulty);
    log.bindValue(9, result.log.retrievability);
    log.bindValue(10, static_cast<int>(result.log.scheduled_days));
    log.bindValue(11, QDateTime::currentDateTimeUtc()
                         .toString(Qt::ISODateWithMs));

    if (!log.exec()) {
        qWarning("ReviewDb: reviewCard: log insert failed: %s",
                 qPrintable(log.lastError().text()));
        return {};
    }

    // 8. Return result as JSON.
    QJsonObject out;
    out[QStringLiteral("card_id")] = cardId;
    out[QStringLiteral("state")] = newState;
    out[QStringLiteral("stability")] = result.memory.stability;
    out[QStringLiteral("difficulty")] = result.memory.difficulty;
    out[QStringLiteral("due")] = nextDue;
    out[QStringLiteral("reps")] = newReps;
    out[QStringLiteral("lapses")] = newLapses;
    out[QStringLiteral("scheduled_days")] = result.log.scheduled_days;
    out[QStringLiteral("retrievability")] = result.log.retrievability;
    out[QStringLiteral("elapsed_days")] = elapsed_days;
    out[QStringLiteral("log_id")] = logId;

    return QString::fromUtf8(
        QJsonDocument(out).toJson(QJsonDocument::Compact));
}

// Queries.

QString ReviewDb::getDueCards(int limit)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT rc.*, t.input_text, t.cleaned_input, t.source_lang, "
        "       t.target_lang, t.result_json, t.created_at AS trans_created_at "
        "FROM review_cards rc "
        "JOIN translations t ON t.id = rc.translation_id "
        "WHERE rc.due <= strftime('%Y-%m-%dT%H:%M:%S','now') "
        "  AND rc.state IN ('learning','review','relearning') "
        "ORDER BY rc.due ASC LIMIT ?"));
    q.bindValue(0, limit);

    if (!q.exec())
        return QStringLiteral("[]");

    QJsonArray rows;
    while (q.next()) {
        QJsonObject row;
        // review_cards columns
        row[QStringLiteral("id")] = q.value(0).toString();
        row[QStringLiteral("translation_id")] = q.value(1).toString();
        row[QStringLiteral("stability")] = q.value(2).toDouble();
        row[QStringLiteral("difficulty")] = q.value(3).toDouble();
        row[QStringLiteral("state")] = q.value(4).toString();
        row[QStringLiteral("due")] = q.value(5).toString();
        row[QStringLiteral("last_review_at")] =
            q.value(6).isNull() ? QJsonValue::Null
                                : QJsonValue(q.value(6).toString());
        row[QStringLiteral("elapsed_days")] = q.value(7).toInt();
        row[QStringLiteral("scheduled_days")] = q.value(8).toInt();
        row[QStringLiteral("reps")] = q.value(9).toInt();
        row[QStringLiteral("lapses")] = q.value(10).toInt();
        // translations columns
        row[QStringLiteral("input_text")] = q.value(13).toString();
        row[QStringLiteral("cleaned_input")] = q.value(14).toString();
        row[QStringLiteral("source_lang")] = q.value(15).toString();
        row[QStringLiteral("target_lang")] = q.value(16).toString();
        row[QStringLiteral("result_json")] = q.value(17).toString();

        // Compute current retrievability from stability and elapsed time
        double stability = q.value(2).toDouble();
        double elapsed_days = 0.0;
        if (!q.value(6).isNull()) {
            elapsed_days = QDateTime::fromString(
                q.value(6).toString(), Qt::ISODate)
                .secsTo(QDateTime::currentDateTimeUtc()) / 86400.0;
            if (elapsed_days < 0.0) elapsed_days = 0.0;
        }
        row[QStringLiteral("retrievability")] =
            m_engine.getRetrievability(stability, elapsed_days);

        rows.append(row);
    }

    return QString::fromUtf8(
        QJsonDocument(rows).toJson(QJsonDocument::Compact));
}

QString ReviewDb::getNewCards(int limit)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT t.id, t.input_text, t.cleaned_input, "
        "       t.source_lang, t.target_lang, t.result_json, t.created_at "
        "FROM translations t "
        "LEFT JOIN review_cards rc ON rc.translation_id = t.id "
        "WHERE rc.id IS NULL "
        "ORDER BY t.created_at ASC LIMIT ?"));
    q.bindValue(0, limit);

    if (!q.exec())
        return QStringLiteral("[]");

    QJsonArray rows;
    while (q.next()) {
        QJsonObject row;
        row[QStringLiteral("id")] = q.value(0).toString();
        row[QStringLiteral("input_text")] = q.value(1).toString();
        row[QStringLiteral("cleaned_input")] = q.value(2).toString();
        row[QStringLiteral("source_lang")] = q.value(3).toString();
        row[QStringLiteral("target_lang")] = q.value(4).toString();
        row[QStringLiteral("result_json")] = q.value(5).toString();
        row[QStringLiteral("created_at")] = q.value(6).toString();
        rows.append(row);
    }

    return QString::fromUtf8(
        QJsonDocument(rows).toJson(QJsonDocument::Compact));
}

QString ReviewDb::getCard(const QString &cardId)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT rc.*, t.input_text, t.cleaned_input, t.source_lang, "
        "       t.target_lang, t.result_json "
        "FROM review_cards rc "
        "JOIN translations t ON t.id = rc.translation_id "
        "WHERE rc.id = ?"));
    q.bindValue(0, cardId);

    if (!q.exec() || !q.next())
        return QString();

    QJsonObject row;
    row[QStringLiteral("id")] = q.value(0).toString();
    row[QStringLiteral("translation_id")] = q.value(1).toString();
    row[QStringLiteral("stability")] = q.value(2).toDouble();
    row[QStringLiteral("difficulty")] = q.value(3).toDouble();
    row[QStringLiteral("state")] = q.value(4).toString();
    row[QStringLiteral("due")] = q.value(5).toString();
    row[QStringLiteral("last_review_at")] =
        q.value(6).isNull() ? QJsonValue::Null
                            : QJsonValue(q.value(6).toString());
    row[QStringLiteral("elapsed_days")] = q.value(7).toInt();
    row[QStringLiteral("scheduled_days")] = q.value(8).toInt();
    row[QStringLiteral("reps")] = q.value(9).toInt();
    row[QStringLiteral("lapses")] = q.value(10).toInt();
    row[QStringLiteral("input_text")] = q.value(13).toString();
    row[QStringLiteral("cleaned_input")] = q.value(14).toString();
    row[QStringLiteral("source_lang")] = q.value(15).toString();
    row[QStringLiteral("target_lang")] = q.value(16).toString();
    row[QStringLiteral("result_json")] = q.value(17).toString();

    // Compute current retrievability
    double R = m_engine.getRetrievability(
        q.value(2).toDouble(),
        QDateTime::fromString(q.value(5).toString(), Qt::ISODate)
            .secsTo(QDateTime::currentDateTimeUtc()) / 86400.0);
    row[QStringLiteral("retrievability")] = R;

    return QString::fromUtf8(
        QJsonDocument(row).toJson(QJsonDocument::Compact));
}

QString ReviewDb::getCardHistory(const QString &cardId, int limit)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT id, rating, state_before, elapsed_days, "
        "       stability_before, stability_after, "
        "       difficulty_before, difficulty_after, "
        "       retrievability_before, scheduled_days, reviewed_at "
        "FROM review_log "
        "WHERE card_id = ? "
        "ORDER BY reviewed_at DESC LIMIT ?"));
    q.bindValue(0, cardId);
    q.bindValue(1, limit);

    if (!q.exec())
        return QStringLiteral("[]");

    QJsonArray rows;
    while (q.next()) {
        QJsonObject row;
        row[QStringLiteral("id")] = q.value(0).toString();
        row[QStringLiteral("rating")] = q.value(1).toInt();
        row[QStringLiteral("state_before")] = q.value(2).toString();
        row[QStringLiteral("elapsed_days")] = q.value(3).toInt();
        row[QStringLiteral("stability_before")] = q.value(4).toDouble();
        row[QStringLiteral("stability_after")] = q.value(5).toDouble();
        row[QStringLiteral("difficulty_before")] = q.value(6).toDouble();
        row[QStringLiteral("difficulty_after")] = q.value(7).toDouble();
        row[QStringLiteral("retrievability_before")] = q.value(8).toDouble();
        row[QStringLiteral("scheduled_days")] = q.value(9).toInt();
        row[QStringLiteral("reviewed_at")] = q.value(10).toString();
        rows.append(row);
    }

    return QString::fromUtf8(
        QJsonDocument(rows).toJson(QJsonDocument::Compact));
}

QString ReviewDb::getStats()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);

    QJsonObject stats;

    // Total cards by state
    QSqlQuery q(db);
    q.exec(QStringLiteral(
        "SELECT state, COUNT(*) AS cnt FROM review_cards GROUP BY state"));
    QJsonObject byState;
    while (q.next())
        byState[q.value(0).toString()] = q.value(1).toInt();
    stats[QStringLiteral("by_state")] = byState;

    // Total reviews
    q.exec(QStringLiteral("SELECT COUNT(*) FROM review_log"));
    if (q.next())
        stats[QStringLiteral("total_reviews")] = q.value(0).toInt();

    // Due count (approximate: due today)
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM review_cards "
        "WHERE due <= strftime('%Y-%m-%dT%H:%M:%S','now') "
        "  AND state IN ('learning','review','relearning')"));
    if (q.next())
        stats[QStringLiteral("due_now")] = q.value(0).toInt();

    // New cards available (translations not yet in review_cards)
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM translations t "
        "LEFT JOIN review_cards rc ON rc.translation_id = t.id "
        "WHERE rc.id IS NULL"));
    if (q.next())
        stats[QStringLiteral("new_available")] = q.value(0).toInt();

    // Total cards
    q.exec(QStringLiteral("SELECT COUNT(*) FROM review_cards"));
    if (q.next())
        stats[QStringLiteral("total_cards")] = q.value(0).toInt();

    // Average stability and difficulty of active cards
    q.exec(QStringLiteral(
        "SELECT AVG(stability), AVG(difficulty) "
        "FROM review_cards "
        "WHERE state IN ('learning','review','relearning') "
        "  AND stability > 0.0"));
    if (q.next()) {
        stats[QStringLiteral("avg_stability")] = q.value(0).toDouble();
        stats[QStringLiteral("avg_difficulty")] = q.value(1).toDouble();
    }

    // Reviews completed today
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM review_log "
        "WHERE reviewed_at >= date('now')"));
    if (q.next())
        stats[QStringLiteral("reviews_today")] = q.value(0).toInt();

    // Cards due within the next 7 days (including already due)
    q.exec(QStringLiteral(
        "SELECT COUNT(*) FROM review_cards "
        "WHERE due <= datetime('now', '+7 days') "
        "  AND state IN ('learning','review','relearning')"));
    if (q.next())
        stats[QStringLiteral("due_this_week")] = q.value(0).toInt();

    return QString::fromUtf8(
        QJsonDocument(stats).toJson(QJsonDocument::Compact));
}

// Direct SQL.

QString ReviewDb::exec(const QString &sql, const QString &jsonParams)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
    if (!db.isValid())
        return QString();

    QSqlQuery q(db);
    if (!q.prepare(sql)) {
        qWarning("ReviewDb::exec: prepare failed: %s",
                 qPrintable(q.lastError().text()));
        return QString();
    }

    QJsonArray params = QJsonDocument::fromJson(jsonParams.toUtf8()).array();
    for (int i = 0; i < params.size(); ++i) {
        const QJsonValue &v = params.at(i);
        if (v.isString())
            q.bindValue(i, v.toString());
        else if (v.isDouble())
            q.bindValue(i, v.toDouble());
        else if (v.isBool())
            q.bindValue(i, v.toBool() ? 1 : 0);
        else if (v.isNull())
            q.bindValue(i, QVariant());
        else
            q.bindValue(i, v.toVariant());
    }

    if (!q.exec()) {
        qWarning("ReviewDb::exec: exec failed: %s",
                 qPrintable(q.lastError().text()));
        return QString();
    }

    if (!q.isSelect())
        return QStringLiteral("[]");

    QJsonArray rows;
    while (q.next()) {
        QJsonObject row;
        for (int i = 0; i < q.record().count(); ++i) {
            QString name = q.record().fieldName(i);
            QVariant val = q.value(i);
            if (val.isNull())
                row[name] = QJsonValue::Null;
            else if (val.metaType().id() == QMetaType::Int
                     || val.metaType().id() == QMetaType::LongLong)
                row[name] = val.toLongLong();
            else if (val.metaType().id() == QMetaType::Double)
                row[name] = val.toDouble();
            else
                row[name] = val.toString();
        }
        rows.append(row);
    }

    return QString::fromUtf8(
        QJsonDocument(rows).toJson(QJsonDocument::Compact));
}
