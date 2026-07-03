// ── Review Database — spaced-repetition persistence ──────
// Manages three tables in ~/.config/linguaspanner/linguaspanner.db:
//   review_cards  — one row per translation tracked
//   review_log    — append-only review history
//   fsrs_params   — global FSRS-6 parameters (singleton row)
//
// Integrates FsrsEngine for algorithm computation on review.
// Pattern follows lingua-spanner's ProcessHelper.
//
// License: GPL-2.0+

#ifndef REVIEWDB_H
#define REVIEWDB_H

#include <QObject>
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QDateTime>

#include "FsrsEngine.h"

class ReviewDb : public QObject
{
    Q_OBJECT

public:
    explicit ReviewDb(QObject *parent = nullptr);
    ~ReviewDb() override;

    // ── Lifecycle ──────────────────────────────────────────

    /// Open (or create) the database and ensure schema.
    /// @param dbPath  — full path to .db file, or ":memory:" for testing.
    ///                  Empty string → default ~/.config/linguaspanner/linguaspanner.db
    /// @returns true on success.
    Q_INVOKABLE bool init(const QString &dbPath = QString());

    /// Close the database connection.
    Q_INVOKABLE void close();

    /// Whether the database is currently open.
    Q_INVOKABLE bool isOpen() const;

    // ── Card creation ──────────────────────────────────────

    /// Create a review card for a translation that doesn't have one yet.
    /// @returns the new card's UUID as string, or empty string on failure.
    Q_INVOKABLE QString createCard(const QString &translationId);

    // ── Review submission ──────────────────────────────────

    /// Submit a review rating for a card. Runs the FSRS-6 algorithm,
    /// updates the card state, and writes to review_log.
    /// @returns JSON result (new card state + review log entry), or empty on error.
    Q_INVOKABLE QString reviewCard(const QString &cardId, int rating);

    // ── Queries (return JSON for QML) ──────────────────────

    /// Get cards due for review (due ≤ now), joined with translations.
    Q_INVOKABLE QString getDueCards(int limit = 50);

    /// Get translations that don't have a review card yet (new items).
    Q_INVOKABLE QString getNewCards(int limit = 20);

    /// Get a single card by ID, joined with translation data.
    Q_INVOKABLE QString getCard(const QString &cardId);

    /// Get the review log for a specific card.
    Q_INVOKABLE QString getCardHistory(const QString &cardId, int limit = 100);

    /// Get aggregate statistics across all cards.
    Q_INVOKABLE QString getStats();

    // ── FSRS parameters ────────────────────────────────────

    /// Read FSRS parameters from the database.
    /// If no row exists, returns the engine defaults.
    Q_INVOKABLE QString loadFsrsParams();

    /// Write FSRS parameters to the database and update the engine.
    /// @param json — JSON object with keys: "w" (array), "desired_retention",
    ///               "max_interval", "enable_fuzzing"
    Q_INVOKABLE bool saveFsrsParams(const QString &json);

    // ── Direct SQL access (matching ProcessHelper.exec()) ──

    /// Execute arbitrary SQL with positional params (JSON array).
    /// SELECT → returns JSON array of row objects.
    /// Other  → returns "[]".
    Q_INVOKABLE QString exec(const QString &sql, const QString &jsonParams = "[]");

    // ── Access the engine for direct formula calls ─────────

    const FsrsEngine &engine() const { return m_engine; }
    FsrsEngine &engine() { return m_engine; }

private:
    // ── Internal helpers ───────────────────────────────────

    QString defaultDbPath() const;
    QString makeConnectionName() const;

    bool ensureSchema();
    void migrateSchema();

    /// Load parameters from fsrs_params table into m_engine.
    void loadEngineParams();

    // ── Members ────────────────────────────────────────────

    QString m_dbPath;
    QString m_connectionName;
    FsrsEngine m_engine;
};

#endif // REVIEWDB_H
