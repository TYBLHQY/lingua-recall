// ── Recall Helper — placeholder C++ QML module ─────────────
// Skeleton for future C++ helper functionality.
// Mirrors ProcessHelper from lingua-spanner but without business logic.
// Extend this class with Q_INVOKABLE methods as needed.

#ifndef RECALLHELPER_H
#define RECALLHELPER_H

#include <QObject>
#include <QtQml>

class RecallHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit RecallHelper(QObject *parent = nullptr);
    ~RecallHelper() override = default;

    /// Placeholder: returns a greeting to verify the module loads.
    Q_INVOKABLE QString hello();

signals:
    /// Placeholder signal for future use.
    void placeholderSignal();
};

#endif // RECALLHELPER_H
