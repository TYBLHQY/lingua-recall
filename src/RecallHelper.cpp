// Recall Helper: Implementation.
// License: GPL-2.0+

#include "RecallHelper.h"
#include "ReviewDb.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

RecallHelper::RecallHelper(QObject *parent)
    : QObject(parent)
{
}

RecallHelper::~RecallHelper()
{
    cancelCommand();
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

// Process execution

QString RecallHelper::cacheFilePath(const QString &prefix, const QString &suffix) const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    QString appDir = dir + QStringLiteral("/linguaspanner");
    QDir().mkpath(appDir);
    return appDir + QStringLiteral("/") + prefix + QStringLiteral("_")
        + QString::number(QDateTime::currentMSecsSinceEpoch()) + suffix;
}

void RecallHelper::runCommand(const QString &command, const QStringList &args)
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        emit commandError(QStringLiteral("A command is already running"));
        return;
    }

    if (!m_process)
        m_process = new QProcess(this);

    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this, [this](int exitCode, QProcess::ExitStatus status) {
            QString stdOut = QString::fromUtf8(m_process->readAllStandardOutput());
            QString stdErr = QString::fromUtf8(m_process->readAllStandardError());
            if (status == QProcess::CrashExit) {
                emit commandError(QStringLiteral("Process crashed (exit code %1)").arg(exitCode));
            } else {
                emit commandFinished(exitCode, stdOut.trimmed(), stdErr.trimmed());
            }
            m_process->deleteLater();
            m_process = nullptr;
        });

    connect(m_process, &QProcess::errorOccurred,
        this, [this, command](QProcess::ProcessError error) {
            QString msg;
            switch (error) {
            case QProcess::FailedToStart:
                msg = command + QStringLiteral(": command not found or failed to start.\nPlease install: pip install edge-tts");
                break;
            case QProcess::Timedout:
                msg = QStringLiteral("Command timed out");
                break;
            default:
                msg = QStringLiteral("Process error: %1").arg(static_cast<int>(error));
                break;
            }
            emit commandError(msg);
            m_process->deleteLater();
            m_process = nullptr;
        });

    m_process->start(command, args);
}

void RecallHelper::cancelCommand()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(3000);
    }
}

bool RecallHelper::fileExists(const QString &filePath) const
{
    return QFileInfo::exists(filePath);
}

void RecallHelper::cleanTtsCache(const QString &cacheDir, int maxFiles)
{
    QDir dir(cacheDir);
    if (!dir.exists()) return;

    auto files = dir.entryInfoList(QDir::Files, QDir::Time | QDir::Reversed);
    if (files.size() <= maxFiles) return;

    for (int i = 0; i < files.size() - maxFiles; ++i)
        QFile::remove(files.at(i).absoluteFilePath());
}

QString RecallHelper::cacheDir(const QString &subdir) const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    QString fullDir = dir + QStringLiteral("/linguaspanner/") + subdir;
    QDir().mkpath(fullDir);
    return fullDir;
}
