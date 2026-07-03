// Recall Helper: Implementation.
// License: GPL-2.0+

#include "RecallHelper.h"
#include "ReviewDb.h"

RecallHelper::RecallHelper(QObject *parent)
    : QObject(parent)
{
}

RecallHelper::~RecallHelper()
{
    delete m_db;
}

QString RecallHelper::hello()
{
    return QStringLiteral("Lingua Recall helper ready.");
}

// Review database lifecycle.

bool RecallHelper::initReviewDb()
{
    if (m_db) {
        if (m_db->isOpen())
            return true;
        delete m_db;
    }

    m_db = new ReviewDb(this);

    if (!m_db->init()) {  // empty → default path
        QString err = QStringLiteral("Failed to open review database at %1")
                          .arg(QStringLiteral("~/.config/linguaspanner/linguaspanner.db"));
        qWarning() << err;
        emit reviewDbError(err);
        return false;
    }

    emit reviewDbReady();
    return true;
}

void RecallHelper::closeReviewDb()
{
    if (m_db)
        m_db->close();
}

bool RecallHelper::isReviewDbOpen() const
{
    return m_db && m_db->isOpen();
}

// Card operations.

QString RecallHelper::createCard(const QString &translationId)
{
    return m_db ? m_db->createCard(translationId) : QString();
}

QString RecallHelper::reviewCard(const QString &cardId, int rating)
{
    return m_db ? m_db->reviewCard(cardId, rating) : QString();
}

QString RecallHelper::getDueCards(int limit)
{
    return m_db ? m_db->getDueCards(limit) : QStringLiteral("[]");
}

QString RecallHelper::getNewCards(int limit)
{
    return m_db ? m_db->getNewCards(limit) : QStringLiteral("[]");
}

QString RecallHelper::getCard(const QString &cardId)
{
    return m_db ? m_db->getCard(cardId) : QString();
}

QString RecallHelper::getCardHistory(const QString &cardId, int limit)
{
    return m_db ? m_db->getCardHistory(cardId, limit) : QStringLiteral("[]");
}

QString RecallHelper::getStats()
{
    return m_db ? m_db->getStats() : QStringLiteral("{}");
}

// FSRS parameters.

QString RecallHelper::loadFsrsParams()
{
    return m_db ? m_db->loadFsrsParams() : QString();
}

bool RecallHelper::saveFsrsParams(const QString &json)
{
    return m_db && m_db->saveFsrsParams(json);
}

// Direct SQL.

QString RecallHelper::exec(const QString &sql, const QString &jsonParams)
{
    return m_db ? m_db->exec(sql, jsonParams) : QString();
}
