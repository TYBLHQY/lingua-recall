#include "RecallHelper.h"

RecallHelper::RecallHelper(QObject *parent)
    : QObject(parent)
{
}

QString RecallHelper::hello()
{
    return QStringLiteral("Lingua Recall helper ready.");
}
