// ReviewDb Unit Tests.
// Uses an in-memory SQLite database (":memory:") so no external
// file is needed. We also create a minimal `translations` table
// to match lingua-spanner's schema, enabling JOIN query tests.
//
// License: GPL-2.0+

#include <QtTest>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlQuery>
#include <QSqlDatabase>

#include "ReviewDb.h"

class tst_ReviewDb : public QObject
{
    Q_OBJECT

private:
    /// Helper: parse a JSON string result.
    static QJsonArray parseArray(const QString &json)
    {
        return QJsonDocument::fromJson(json.toUtf8()).array();
    }
    static QJsonObject parseObj(const QString &json)
    {
        return QJsonDocument::fromJson(json.toUtf8()).object();
    }

    /// Seed the translations table with test data.
    static void seedTranslations(const QString &connName)
    {
        // Minimal helper: insert some test entries
        QSqlDatabase db = QSqlDatabase::database(connName, false);
        QSqlQuery q(db);
        q.exec(QStringLiteral(
            "INSERT INTO translations (id, input_text, cleaned_input, engine, "
            "  source_lang, target_lang, result_json) VALUES "
            "('t1','hello','hello','test','en','zh','{}'),"
            "('t2','world','world','test','en','zh','{}'),"
            "('t3','test','test','test','en','zh','{}'),"
            "('t4','foo','foo','test','en','zh','{}'),"
            "('t5','bar','bar','test','en','zh','{}')"));
    }

    ReviewDb *m_db = nullptr;

private slots:
    void init()
    {
        m_db = new ReviewDb(this);

        // Connect to in-memory database
        QVERIFY(m_db->init(QStringLiteral(":memory:")));

        // Also create the translations table (matching lingua-spanner schema)
        // so our JOIN queries work
        QSqlDatabase db = QSqlDatabase::database(
            QStringLiteral("reviewdb_%1").arg(
                reinterpret_cast<quintptr>(m_db), 0, 16), false);
        QSqlQuery q(db);
        q.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS translations ("
            "  id            TEXT    PRIMARY KEY,"
            "  input_text    TEXT    NOT NULL,"
            "  cleaned_input TEXT    NOT NULL DEFAULT '',"
            "  engine        TEXT    NOT NULL,"
            "  source_lang   TEXT    NOT NULL DEFAULT '',"
            "  target_lang   TEXT    NOT NULL DEFAULT '',"
            "  result_json   TEXT    NOT NULL DEFAULT '{}',"
            "  created_at    TEXT    NOT NULL "
            "    DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now'))"
            ")"));

        seedTranslations(
            QStringLiteral("reviewdb_%1").arg(
                reinterpret_cast<quintptr>(m_db), 0, 16));
    }

    void cleanup()
    {
        delete m_db;
        m_db = nullptr;
    }

    // Schema tests.

    void test_ensureSchema_createsTables()
    {
        // Tables should exist after init()
        QSqlDatabase db = QSqlDatabase::database(
            QStringLiteral("reviewdb_%1").arg(
                reinterpret_cast<quintptr>(m_db), 0, 16), false);

        auto tableExists = [&](const QString &name) {
            QSqlQuery q(db);
            q.exec(QStringLiteral(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='%1'")
                       .arg(name));
            return q.next();
        };

        QVERIFY(tableExists(QStringLiteral("review_cards")));
        QVERIFY(tableExists(QStringLiteral("review_log")));
        QVERIFY(tableExists(QStringLiteral("fsrs_params")));
    }

    void test_fsrsParams_singletonExists()
    {
        auto stats = parseObj(m_db->getStats());
        QVERIFY(stats.contains(QStringLiteral("by_state")));

        // fsrs_params should have its singleton row
        auto params = parseObj(m_db->loadFsrsParams());
        QCOMPARE(params[QStringLiteral("desired_retention")].toDouble(), 0.9);
        QVERIFY(params.contains(QStringLiteral("w")));
        QCOMPARE(params[QStringLiteral("w")].toArray().size(), 21);
    }

    // Card creation.

    void test_createCard_success()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));
        QVERIFY(!cid.isEmpty());
        QVERIFY(cid.length() > 10); // looks like a UUID
    }

    void test_createCard_duplicateReturnsEmpty()
    {
        QString c1 = m_db->createCard(QStringLiteral("t1"));
        QVERIFY(!c1.isEmpty());

        QString c2 = m_db->createCard(QStringLiteral("t1"));
        QVERIFY(c2.isEmpty()); // duplicate
    }

    void test_createCard_differentTranslations()
    {
        QString c1 = m_db->createCard(QStringLiteral("t1"));
        QString c2 = m_db->createCard(QStringLiteral("t2"));
        QVERIFY(!c1.isEmpty());
        QVERIFY(!c2.isEmpty());
        QVERIFY(c1 != c2);
    }

    // New cards query.

    void test_getNewCards_returnsAllWhenNoneCreated()
    {
        auto cards = parseArray(m_db->getNewCards(10));
        QCOMPARE(cards.size(), 5); // all 5 seeded translations
    }

    void test_getNewCards_excludesCreated()
    {
        m_db->createCard(QStringLiteral("t1"));
        m_db->createCard(QStringLiteral("t3"));

        auto cards = parseArray(m_db->getNewCards(10));
        QCOMPARE(cards.size(), 3); // t2, t4, t5 remain
    }

    // Review submission.

    void test_reviewCard_firstRating_good()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));
        QVERIFY(!cid.isEmpty());

        QString result = m_db->reviewCard(cid, 3); // Good
        QVERIFY(!result.isEmpty());

        auto obj = parseObj(result);
        QCOMPARE(obj[QStringLiteral("card_id")].toString(), cid);
        QCOMPARE(obj[QStringLiteral("state")].toString(),
                 QStringLiteral("learning"));
        QVERIFY(obj[QStringLiteral("stability")].toDouble() > 0);
        QVERIFY(obj[QStringLiteral("scheduled_days")].toDouble() >= 0.5);

        // Should have created a review_log entry
        auto history = parseArray(m_db->getCardHistory(cid));
        QCOMPARE(history.size(), 1);
        QCOMPARE(history[0].toObject()[QStringLiteral("rating")].toInt(), 3);
    }

    void test_reviewCard_secondReview_increasesStability()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));

        // First: Good → initial stability
        auto r1 = parseObj(m_db->reviewCard(cid, 3));
        double s1 = r1[QStringLiteral("stability")].toDouble();
        QVERIFY2(s1 > 0, qPrintable(
            QStringLiteral("First review gave S=%1").arg(s1)));

        // Verify card was updated in DB
        auto card1 = parseObj(m_db->getCard(cid));
        double sDb1 = card1[QStringLiteral("stability")].toDouble();
        qDebug() << "After first review: card stability =" << sDb1
                 << "state =" << card1["state"].toString()
                 << "last_review_at =" << card1["last_review_at"].toString()
                 << "reps =" << card1["reps"].toInt();

        // Set last_review_at to 7 days ago so the second review
        // won't be treated as same-day
        {
            QSqlDatabase db = QSqlDatabase::database(
                QStringLiteral("reviewdb_%1").arg(
                    reinterpret_cast<quintptr>(m_db), 0, 16), false);
            QSqlQuery q(db);
            q.prepare(QStringLiteral(
                "UPDATE review_cards SET last_review_at = "
                "strftime('%Y-%m-%dT%H:%M:%S','now','-7 days'), "
                "elapsed_days = 7 WHERE id = ?"));
            q.bindValue(0, cid);
            QVERIFY(q.exec());
            qDebug() << "Updated last_review_at to 7 days ago,"
                     << "rows affected:" << q.numRowsAffected();
        }

        // Verify the update took effect
        auto cardBefore2 = parseObj(m_db->getCard(cid));
        qDebug() << "Before second review: last_review_at ="
                 << cardBefore2["last_review_at"].toString()
                 << "elapsed_days =" << cardBefore2["elapsed_days"].toInt();

        // Second: Good (7 days later) → stability must increase
        auto r2 = parseObj(m_db->reviewCard(cid, 3));
        double s2 = r2[QStringLiteral("stability")].toDouble();

        qDebug() << "After second review: stability =" << s2
                 << "reps =" << r2["reps"].toInt()
                 << "scheduled_days =" << r2["scheduled_days"].toDouble();

        QVERIFY2(s2 > s1, qPrintable(
            QStringLiteral("S %1 should increase to > %2 on success review")
                .arg(s1).arg(s2)));
        QCOMPARE(r2[QStringLiteral("reps")].toInt(), 2);
    }

    void test_reviewCard_againDropsStability()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));

        // First: Good → build stability
        m_db->reviewCard(cid, 3);
        auto cardBefore = parseObj(m_db->getCard(cid));
        double sBefore = cardBefore[QStringLiteral("stability")].toDouble();

        // Second: Again → should drop
        auto r2 = parseObj(m_db->reviewCard(cid, 1));
        double sAfter = r2[QStringLiteral("stability")].toDouble();

        QVERIFY(sAfter <= sBefore); // failure → stability drops
        QCOMPARE(r2[QStringLiteral("lapses")].toInt(), 1);
    }

    void test_reviewCard_invalidRating()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));

        QString r = m_db->reviewCard(cid, 5); // invalid
        QVERIFY(r.isEmpty());
    }

    void test_reviewCard_nonexistentCard()
    {
        QString r = m_db->reviewCard(QStringLiteral("no-such-card"), 3);
        QVERIFY(r.isEmpty());
    }

    // Due cards query.

    void test_getDueCards_includesOverdue()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));

        // Manually set due to past to simulate overdue
        QSqlDatabase db = QSqlDatabase::database(
            QStringLiteral("reviewdb_%1").arg(
                reinterpret_cast<quintptr>(m_db), 0, 16), false);
        QSqlQuery q(db);
        q.prepare(QStringLiteral(
            "UPDATE review_cards SET due = '2020-01-01T00:00:00', "
            "  state = 'review', elapsed_days = 100 "
            "WHERE id = ?"));
        q.bindValue(0, cid);
        q.exec();

        auto dueCards = parseArray(m_db->getDueCards(10));
        QCOMPARE(dueCards.size(), 1);
        QCOMPARE(dueCards[0].toObject()[QStringLiteral("id")].toString(), cid);
    }

    void test_getDueCards_excludesFutureCards()
    {
        m_db->createCard(QStringLiteral("t1"));

        // The card defaults to due = now, which is due
        // But if we set it far in the future, it shouldn't show
        QSqlDatabase db = QSqlDatabase::database(
            QStringLiteral("reviewdb_%1").arg(
                reinterpret_cast<quintptr>(m_db), 0, 16), false);
        // Find the card ID
        auto cards = parseArray(m_db->getNewCards(1));
        // All cards are new (not in review_cards), so getDueCards returns nothing
        auto dueCards = parseArray(m_db->getDueCards(10));
        QCOMPARE(dueCards.size(), 0);
    }

    // Card get / history.

    void test_getCard_returnsCardWithTranslations()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));
        m_db->reviewCard(cid, 3);

        auto card = parseObj(m_db->getCard(cid));
        QCOMPARE(card[QStringLiteral("id")].toString(), cid);
        QCOMPARE(card[QStringLiteral("input_text")].toString(),
                 QStringLiteral("hello"));
        QVERIFY(card.contains(QStringLiteral("retrievability")));
    }

    void test_getCardHistory_orderedByTime()
    {
        QString cid = m_db->createCard(QStringLiteral("t1"));

        auto setLastReview = [&](const QString &offset) {
            QSqlDatabase db = QSqlDatabase::database(
                QStringLiteral("reviewdb_%1").arg(
                    reinterpret_cast<quintptr>(m_db), 0, 16), false);
            QSqlQuery q(db);
            q.prepare(QStringLiteral(
                "UPDATE review_cards SET last_review_at = "
                "strftime('%%Y-%%m-%%dT%%H:%%M:%%S','now',?) "
                "WHERE id = ?"));
            q.bindValue(0, offset);
            q.bindValue(1, cid);
            q.exec();
        };

        // Add small sleep to ensure review_log timestamps differ
        // (Qt ISODateWithMs provides ms precision; 5ms gap is enough)
        auto reviewWithGap = [&](int rating, const QString &offset) {
            setLastReview(offset);
            m_db->reviewCard(cid, rating);
            QTest::qSleep(5);
        };

        reviewWithGap(3, QStringLiteral("-10 days"));
        reviewWithGap(4, QStringLiteral("-5 days"));
        reviewWithGap(2, QStringLiteral("0 seconds"));

        auto history = parseArray(m_db->getCardHistory(cid, 10));
        QCOMPARE(history.size(), 3);
        // Most recent first
        QCOMPARE(history[0].toObject()[QStringLiteral("rating")].toInt(), 2);
        QCOMPARE(history[1].toObject()[QStringLiteral("rating")].toInt(), 4);
        QCOMPARE(history[2].toObject()[QStringLiteral("rating")].toInt(), 3);
    }

    // Stats.

    void test_getStats_aggregatesCorrectly()
    {
        m_db->createCard(QStringLiteral("t1"));
        m_db->createCard(QStringLiteral("t2"));
        m_db->createCard(QStringLiteral("t3"));

        m_db->reviewCard(m_db->createCard(QStringLiteral("t4")), 3);
        m_db->reviewCard(m_db->createCard(QStringLiteral("t5")), 3);

        auto stats = parseObj(m_db->getStats());
        QCOMPARE(stats[QStringLiteral("total_reviews")].toInt(), 2);
    }

    // FSRS parameters.

    void test_saveFsrsParams_updatesEngine()
    {
        QString newParams = QStringLiteral(
            R"({"w":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21],)"
            R"("desired_retention":0.85,"max_interval":3650,"enable_fuzzing":0})");

        QVERIFY(m_db->saveFsrsParams(newParams));

        // Verify the engine picked up the new parameters
        const auto &p = m_db->engine().parameters();
        QCOMPARE(p.desired_retention, 0.85);
        QCOMPARE(p.max_interval, 3650);
        QCOMPARE(p.w[0], 1.0);
        QCOMPARE(p.w[20], 21.0);

        // Verify the DB also has them
        auto loaded = parseObj(m_db->loadFsrsParams());
        QCOMPARE(loaded[QStringLiteral("desired_retention")].toDouble(), 0.85);
    }

    // Direct SQL.

    void test_exec_select()
    {
        // exec raw SQL
        auto result = parseArray(m_db->exec(
            QStringLiteral("SELECT id, input_text FROM translations "
                           "WHERE source_lang = ? ORDER BY input_text ASC"),
            QStringLiteral(R"(["en"])")));
        QCOMPARE(result.size(), 5);
        QCOMPARE(result[0].toObject()[QStringLiteral("input_text")].toString(),
                 QStringLiteral("bar"));
    }

    // Lifecycle.

    void test_init_twiceIsSafe()
    {
        QVERIFY(m_db->isOpen());
        QVERIFY(m_db->init(QStringLiteral(":memory:"))); // re-init
        QVERIFY(m_db->isOpen());
    }

    void test_closeAndReopen()
    {
        m_db->close();
        QVERIFY(!m_db->isOpen());

        QVERIFY(m_db->init(QStringLiteral(":memory:")));
        QVERIFY(m_db->isOpen());
    }
};

QTEST_MAIN(tst_ReviewDb)
#include "tst_ReviewDb.moc"
