// ── Recall Helper — QML façade for ReviewDb + FsrsEngine ─
// License: GPL-2.0+

#ifndef RECALLHELPER_H
#define RECALLHELPER_H

#include <QObject>
#include <QtQml>

class ReviewDb;

class RecallHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit RecallHelper(QObject *parent = nullptr);
    ~RecallHelper() override;

    // ── Placeholder (legacy) ──────────────────────────────
    Q_INVOKABLE QString hello();

    // ── Review database lifecycle ─────────────────────────
    /// Initialize the review database (opens ~/.config/linguaspanner/linguaspanner.db,
    /// creates tables if needed, loads FSRS parameters).
    /// Call once from QML Component.onCompleted.
    Q_INVOKABLE bool initReviewDb();

    /// Close the review database connection.
    Q_INVOKABLE void closeReviewDb();

    /// Whether the review database is open.
    Q_INVOKABLE bool isReviewDbOpen() const;

    // ── Card operations (pass-through to ReviewDb) ────────
    Q_INVOKABLE QString createCard(const QString &translationId);
    Q_INVOKABLE QString reviewCard(const QString &cardId, int rating);
    Q_INVOKABLE QString getDueCards(int limit = 50);
    Q_INVOKABLE QString getNewCards(int limit = 20);
    Q_INVOKABLE QString getCard(const QString &cardId);
    Q_INVOKABLE QString getCardHistory(const QString &cardId, int limit = 100);
    Q_INVOKABLE QString getStats();

    // ── FSRS parameters ──────────────────────────────────
    Q_INVOKABLE QString loadFsrsParams();
    Q_INVOKABLE bool saveFsrsParams(const QString &json);

    // ── Direct SQL ────────────────────────────────────────
    Q_INVOKABLE QString exec(const QString &sql, const QString &jsonParams = "[]");

signals:
    void reviewDbReady();
    void reviewDbError(const QString &message);

private:
    ReviewDb *m_db = nullptr;
};

#endif // RECALLHELPER_H
