// ── FSRS-6 Algorithm Engine ─────────────────────────────────
// Pure C++ implementation of the Free Spaced Repetition Scheduler v6.
// Zero Qt/QML dependency — only <cmath> and <array>.
//
// Reference: https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
// Reference implementation: github.com/open-spaced-repetition/fsrs-rs/src/model.rs
//
// Notation matches the FSRS-6 paper:
//   S (Stability)  — days until recall probability drops to 90%
//   D (Difficulty) — inherent card difficulty, range [1, 10]
//   R (Retrievability) — predicted recall probability (computed, not stored)
//   G (Grade) — 1=Again, 2=Hard, 3=Good, 4=Easy
//
// License: GPL-2.0+

#ifndef FSRSEngine_H
#define FSRSEngine_H

#include <array>
#include <cmath>
#include <cstdint>

class FsrsEngine
{
public:
    // ── Data types ─────────────────────────────────────────

    /// FSRS-6 model parameters (21 learned weights + scheduler settings).
    /// Default values are the optimized FSRS-6 defaults from the reference
    /// implementation.
    struct Parameters {
        /// 21 learned weights w[0]…w[20]
        ///  w[0..3]  — initial stability S₀(Again/Hard/Good/Easy)
        ///  w[4,w5]  — initial difficulty D₀
        ///  w[6]     — difficulty delta multiplier
        ///  w[7]     — difficulty mean-reversion weight
        ///  w[8..10] — success stability multiplier (exp factor, S power, R factor)
        ///  w[11..14]— failure stability (scale, D power, S power, R factor)
        ///  w[15]    — Hard penalty (multiplied into SInc)
        ///  w[16]    — Easy bonus (multiplied into SInc)
        ///  w[17..19]— same-day review (grade offset, offset shift, S saturation)
        ///  w[20]    — forgetting-curve decay exponent (trainable)
        std::array<double, 21> w = {
            0.212,   1.2931,  2.3065,  8.2956,   // S₀
            6.4133,  0.8334,                      // D₀
            3.0194,  0.001,                       // diff delta, mean reversion
            1.8722,  0.1666,  0.796,              // success: exp, S-power, R-factor
            1.4835,  0.0614,  0.2629,  1.6483,   // failure: scale, D-power, S-power, R-factor
            0.6014,                               // Hard penalty
            1.8729,                               // Easy bonus
            0.5425,  0.0912,  0.0658,             // same-day: grade, offset, saturat.
            0.1542                                // forgetting-curve decay
        };

        /// Target retention probability (default 0.9 = 90%)
        double desired_retention = 0.9;

        /// Maximum interval in days (default 36500 ≈ 100 years)
        int max_interval = 36500;
    };

    /// Memory state of a card (persistent across reviews).
    struct MemoryState {
        double stability = 0.0;   // S (days)
        double difficulty = 0.0;  // D [1, 10]
    };

    /// One review log entry (append-only, written to DB later).
    struct ReviewLog {
        int rating = 0;                   // 1=Again .. 4=Easy
        MemoryState memory_before;         // S and D before review
        MemoryState memory_after;          // S and D after review
        double retrievability = 0.0;       // R before review
        double elapsed_days = 0.0;         // days since last review
        double scheduled_days = 0.0;       // next interval after review
    };

    /// Review result: new memory state + log entry.
    struct ReviewResult {
        MemoryState memory;       // updated S and D after review
        ReviewLog log;            // immutable review log entry
    };

    // ── Construction ───────────────────────────────────────

    FsrsEngine() = default;
    explicit FsrsEngine(const Parameters &params);

    // ── Core API ───────────────────────────────────────────

    /// Process the first review of a new card (S == 0).
    /// Initializes stability and difficulty from the rating.
    MemoryState initMemory(int rating) const;

    /// Process a subsequent review.
    /// @param current   — current memory state (S, D)
    /// @param rating    — 1=Again, 2=Hard, 3=Good, 4=Easy
    /// @param elapsed   — days elapsed since last review (≥ 0)
    ReviewResult review(const MemoryState &current, int rating, double elapsed_days) const;

    /// Compute predicted retrievability at a given elapsed time.
    /// @param stability — current S value
    /// @param elapsed   — days since last review
    double getRetrievability(double stability, double elapsed_days) const;

    /// Compute next interval (in days) for a given stability.
    /// Uses the engine's desired_retention.
    double getInterval(double stability) const;

    /// Compute next interval for a custom desired retention.
    double getInterval(double stability, double desired_retention) const;

    // ── Parameter access ───────────────────────────────────

    const Parameters &parameters() const { return m_params; }
    void setParameters(const Parameters &params);

private:
    Parameters m_params;

    // ── Internal formula helpers ───────────────────────────

    /// Forgetting curve: R(t, S) = (1 + factor·t/S)^(-w[20])
    double forgettingCurve(double stability, double elapsed_days) const;

    /// Factor used in both forgetting curve and interval calculation:
    /// factor = 0.9^(-1/w[20]) - 1
    double forgetFactor() const;

    /// Initial stability after first review: S₀(G) = w[G-1]
    double initStability(int rating) const;

    /// Initial difficulty after first review: D₀(G) = w₄ - e^(w₅·(G-1)) + 1
    double initDifficulty(int rating) const;

    /// Stability after a successful (non same-day) review.
    double stabilitySuccess(const MemoryState &current,
                            double retrievability, int rating) const;

    /// Stability after failed review (Again, non same-day).
    double stabilityFail(const MemoryState &current,
                         double retrievability) const;

    /// Stability change for same-day review (delta_t == 0).
    double stabilityShortTerm(const MemoryState &current, int rating) const;

    /// Difficulty update for any rating (success or failure path).
    double nextDifficulty(double current_difficulty, int rating) const;

    /// Clamp difficulty to [1, 10].
    static constexpr double clampDifficulty(double d);
};

// ── Inline implementations ─────────────────────────────────

constexpr double FsrsEngine::clampDifficulty(double d)
{
    return std::max(1.0, std::min(10.0, d));
}

#endif // FSRSEngine_H
