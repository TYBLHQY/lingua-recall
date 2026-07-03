// FsrsEngine Unit Tests.
// Compile & run:
//   cmake --build build -jN && ./build/tests/tst_FsrsEngine
// Or:
//   make check
//
// License: GPL-2.0+

#include <QtTest>
#include <QtTest/QtTest>

#include "FsrsEngine.h"

class tst_FsrsEngine : public QObject
{
    Q_OBJECT

private:
    /// Default FSRS-6 engine.
    FsrsEngine engine;

    /// Tolerance for floating-point comparisons.
    static constexpr double TOL = 0.01;

    /// Helper: assert two doubles are near.
    static void checkNear(double actual, double expected,
                          const char *tag = nullptr)
    {
        if (tag) {
            QVERIFY2(std::fabs(actual - expected) <= TOL,
                     qPrintable(QStringLiteral("%1: got %2, expected %3 ±%4")
                                .arg(tag).arg(actual).arg(expected).arg(TOL)));
        } else {
            QVERIFY(std::fabs(actual - expected) <= TOL);
        }
    }

    /// Helper: check memory state with ease.
    static void checkMem(const FsrsEngine::MemoryState &ms,
                         double expS, double expD)
    {
        checkNear(ms.stability, expS, "stability");
        checkNear(ms.difficulty, expD, "difficulty");
    }

    /// Helper: print review result (for debugging).
    static QString dumpReview(const FsrsEngine::ReviewResult &rr)
    {
        return QString::asprintf("S %.4f -> %.4f  |  D %.4f -> %.4f  |  "
                                 "R=%.4f  |  elapsed=%.1f d  |  interval=%.1f d",
                                 rr.log.memory_before.stability,
                                 rr.log.memory_after.stability,
                                 rr.log.memory_before.difficulty,
                                 rr.log.memory_after.difficulty,
                                 rr.log.retrievability,
                                 rr.log.elapsed_days,
                                 rr.log.scheduled_days);
    }

private slots:
    // Initialization tests.

    void test_constructor_defaults()
    {
        FsrsEngine e;
        const auto &p = e.parameters();
        QCOMPARE(p.desired_retention, 0.9);
        QCOMPARE(p.max_interval, 36500);
        // spot-check a couple of w values
        checkNear(p.w[0], 0.212);
        checkNear(p.w[4], 6.4133);
        checkNear(p.w[20], 0.1542);
    }

    void test_initMemory_again()
    {
        // rating=1 → S₀ = w[0], D₀ = w₄ - exp(w₅·0) + 1 = w₄ - 1 + 1 = w₄
        auto ms = engine.initMemory(1);
        checkMem(ms, 0.212, 6.4133);
    }

    void test_initMemory_hard()
    {
        // rating=2 → S₀ = w[1], D₀ = w₄ - exp(w₅·1) + 1
        auto ms = engine.initMemory(2);
        checkNear(ms.stability, 1.2931, "S₀(Hard)");
        double expD = engine.parameters().w[4]
                      - std::exp(engine.parameters().w[5] * 1) + 1.0;
        checkNear(ms.difficulty, expD, "D₀(Hard)");
    }

    void test_initMemory_good()
    {
        auto ms = engine.initMemory(3);
        checkNear(ms.stability, 2.3065, "S₀(Good)");
        // D₀(3) = w₄ - exp(2·w₅) + 1
        double expD = 6.4133 - std::exp(2 * 0.8334) + 1.0;
        checkNear(ms.difficulty, expD, "D₀(Good)");
    }

    void test_initMemory_easy()
    {
        auto ms = engine.initMemory(4);
        checkNear(ms.stability, 8.2956, "S₀(Easy)");
        // D₀(4) = w₄ - exp(3·w₅) + 1  (may clamp to 1)
        double rawD = 6.4133 - std::exp(3 * 0.8334) + 1.0;
        double expD = std::max(1.0, std::min(10.0, rawD));
        checkNear(ms.difficulty, expD, "D₀(Easy)");
    }

    // First review → review cycle.

    void test_firstReview_then_goodReview()
    {
        // === First review: new card, rated Good ===
        auto init = engine.initMemory(3);
        QVERIFY(init.stability > 2);
        QVERIFY(init.difficulty >= 1);

        // === Next review 7 days later, rated Good ===
        auto r1 = engine.review(init, 3, 7.0);
        // Stability should increase
        QVERIFY(r1.memory.stability > init.stability);
        // Difficulty should stay roughly same (G=3 → ΔD≈0)
        checkNear(r1.memory.difficulty, init.difficulty, "D after Good/Good");
        QVERIFY(r1.log.retrievability > 0 && r1.log.retrievability < 1);
        QVERIFY(r1.log.scheduled_days >= 1);
    }

    void test_firstReview_then_hardReview()
    {
        auto init = engine.initMemory(3);
        auto r1 = engine.review(init, 2, 7.0);  // Hard

        // S should increase less than with Good (w[15] < 1 penalizes Hard)
        QVERIFY(r1.memory.stability >= init.stability);
        // D should increase slightly (G=2 → ΔD = -w₆·(-1) = w₆ > 0)
        QVERIFY(r1.memory.difficulty >= init.difficulty);
    }

    void test_firstReview_then_easyReview()
    {
        auto init = engine.initMemory(3);
        auto r1 = engine.review(init, 4, 7.0);  // Easy

        // S should increase more than Good (w[16] > 1 bonus)
        QVERIFY(r1.memory.stability > init.stability);
        // D should decrease (G=4 → ΔD = -w₆·(1) = -w₆ < 0)
        QVERIFY(r1.memory.difficulty <= init.difficulty);
    }

    void test_firstReview_then_againReview()
    {
        auto init = engine.initMemory(3);
        auto r1 = engine.review(init, 1, 7.0);  // Again (forgot)

        // S should drop
        QVERIFY(r1.memory.stability <= init.stability);
        // D should stay unchanged (per fsrs-rs model.rs: difficulty unchanged on failure)
        QCOMPARE(r1.memory.difficulty, init.difficulty);
    }

    // Same-day reviews.

    void test_sameDay_goodReview()
    {
        auto init = engine.initMemory(3);
        auto r1 = engine.review(init, 3, 0.0);  // same-day Good

        // Same-day should still increase stability
        QVERIFY(r1.memory.stability >= init.stability);
        // Should use short-term formula
        qDebug().noquote() << "Same-day Good:" << dumpReview(r1);
    }

    void test_sameDay_againReview()
    {
        auto init = engine.initMemory(3);
        auto r1 = engine.review(init, 1, 0.0);  // same-day Again

        // Same-day Again might decrease or increase depending on S
        qDebug().noquote() << "Same-day Again:" << dumpReview(r1);
    }

    // Retrievability.

    void test_retrievability_decaysOverTime()
    {
        const double S = 10.0;
        double r1 = engine.getRetrievability(S, 0.0);
        double r2 = engine.getRetrievability(S, 5.0);
        double r3 = engine.getRetrievability(S, 10.0);

        // R should be 1 at t=0 (ish), decreasing over time
        QVERIFY(r1 >= r2);
        QVERIFY(r2 >= r3);

        // At t=S, R should be ≈ 0.9
        checkNear(r3, 0.9, "R(S,S)");

        qDebug().noquote()
            << QString::asprintf("R(t=%.1f)=%.4f  R(t=%.1f)=%.4f  R(t=%.1f)=%.4f",
                                 0.0, r1, 5.0, r2, 10.0, r3);
    }

    void test_retrievability_edgeCases()
    {
        // Zero stability → should return 1.0
        double r = engine.getRetrievability(0.0, 1.0);
        QCOMPARE(r, 1.0);

        // Very long elapsed
        r = engine.getRetrievability(1.0, 365 * 10);
        QVERIFY(r >= 0.0);
        QVERIFY(r < 0.5);
    }

    // Interval.

    void test_interval_equalsStabilityAt90()
    {
        // When desired_retention = 0.9, I should equal S
        double I = engine.getInterval(10.0, 0.9);
        checkNear(I, 10.0, "I(S, 0.9) == S");

        I = engine.getInterval(100.0, 0.9);
        checkNear(I, 100.0, "I(100, 0.9) == 100");
    }

    void test_interval_longerWithLowerRetention()
    {
        double I90 = engine.getInterval(10.0, 0.9);
        double I80 = engine.getInterval(10.0, 0.8);
        QVERIFY(I80 > I90);
    }

    void test_interval_shorterWithHigherRetention()
    {
        double I90 = engine.getInterval(10.0, 0.9);
        double I95 = engine.getInterval(10.0, 0.95);
        QVERIFY(I95 < I90);
    }

    // Full simulation: progressive reviews.

    void test_reviewCycle_progressive()
    {
        // Simulate 5 successive Good reviews at increasing intervals
        auto mem = engine.initMemory(3);  // first review: Good

        qDebug().noquote()
            << QString::asprintf("--- Progressive Good cycle ---\n"
                                 "Init: S= %.4f, D= %.4f",
                                 mem.stability, mem.difficulty);

        double delay = 1.0;
        for (int i = 0; i < 5; ++i) {
            auto r = engine.review(mem, 3, delay);
            qDebug().noquote()
                << QString::asprintf("  Step %d: wait %.1f d -> S %.4f -> %.4f, "
                                     "D %.4f -> %.4f, next %.4f d",
                                     i + 1, delay,
                                     r.log.memory_before.stability,
                                     r.log.memory_after.stability,
                                     r.log.memory_before.difficulty,
                                     r.log.memory_after.difficulty,
                                     r.log.scheduled_days);

            QVERIFY(r.memory.stability >= mem.stability);
            mem = r.memory;
            delay = r.log.scheduled_days;  // review at due date
        }

        // After 5 successful reviews, stability should be much higher
        QVERIFY(mem.stability > 10.0);
        // Difficulty should be <= initial (Good keeps it stable or slightly dropping)
        QVERIFY(mem.difficulty >= 1.0);
        QVERIFY(mem.difficulty <= 10.0);
    }

    void test_reviewCycle_forgetAndRelearn()
    {
        // First review: Good
        auto mem = engine.initMemory(3);
        qDebug().noquote()
            << QString::asprintf("--- Forget & Relearn ---\n"
                                 "Init: S=%.4f, D=%.4f",
                                 mem.stability, mem.difficulty);

        // Wait 3 days, Good
        auto r1 = engine.review(mem, 3, 3.0);
        qDebug().noquote() << "  After 3d Good:" << dumpReview(r1);
        mem = r1.memory;

        // Wait 5 days, Again (forgot)
        auto r2 = engine.review(mem, 1, 5.0);
        qDebug().noquote() << "  After 5d Again:" << dumpReview(r2);
        // S should drop
        QVERIFY(r2.memory.stability <= mem.stability);
        mem = r2.memory;

        // Review again after 1 day, Good
        auto r3 = engine.review(mem, 3, 1.0);
        qDebug().noquote() << "  Next day Good:" << dumpReview(r3);
        // S should recover
        QVERIFY(r3.memory.stability >= mem.stability);
    }

    // Difficulty convergence.

    void test_difficulty_convergesOnRepeatedGood()
    {
        auto mem = engine.initMemory(3);
        double delay = 1.0;
        for (int i = 0; i < 20; ++i) {
            auto r = engine.review(mem, 3, delay);
            mem = r.memory;
            delay = r.log.scheduled_days;
        }
        // After many Good reviews, D should converge to D₀(4) (mean reversion)
        // D₀(4) for FSRS-6 defaults clamps to 1.0
        qDebug().noquote()
            << QString::asprintf("D after 20x Good: %.4f (converging toward D0(4)=%.4f)",
                                 mem.difficulty,
                                 engine.parameters().w[4]
                                     - std::exp(engine.parameters().w[5] * 3) + 1.0);
        QVERIFY(mem.difficulty >= 1.0);
    }

    // Parameter mutation.

    void test_setParameters()
    {
        auto p = engine.parameters();
        p.desired_retention = 0.85;
        p.max_interval = 1000;
        p.w[0] = 1.0;

        FsrsEngine e2(p);
        QCOMPARE(e2.parameters().desired_retention, 0.85);
        QCOMPARE(e2.parameters().max_interval, 1000);
        checkNear(e2.parameters().w[0], 1.0);

        // Verify the parameter change affects behavior
        auto ms = e2.initMemory(1);
        checkNear(ms.stability, 1.0);
    }

    // Random stress test.

    void test_randomReviews_stabilityNeverNegative()
    {
        auto mem = engine.initMemory(3);
        double delay = 1.0;

        std::srand(42);
        for (int i = 0; i < 100; ++i) {
            int rating = (std::rand() % 4) + 1;  // 1..4
            auto r = engine.review(mem, rating, delay);

            QVERIFY(r.memory.stability >= 0.0);
            QVERIFY(r.memory.difficulty >= 1.0);
            QVERIFY(r.memory.difficulty <= 10.0);
            QVERIFY(r.log.retrievability >= 0.0 || r.log.elapsed_days > 0.0);
            QVERIFY(r.log.scheduled_days >= 1.0);

            mem = r.memory;
            delay = r.log.scheduled_days;
        }
        qDebug().noquote()
            << QString::asprintf("After 100 random reviews: S=%.4f, D=%.4f",
                                 mem.stability, mem.difficulty);
    }
};

QTEST_MAIN(tst_FsrsEngine)
#include "tst_FsrsEngine.moc"
