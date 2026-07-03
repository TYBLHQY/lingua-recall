// FSRS-6 Algorithm Engine: Implementation.
// All formulas verified against:
//   https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
//   github.com/open-spaced-repetition/fsrs-rs/src/model.rs
//
// License: GPL-2.0+

#include "FsrsEngine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

// Construction.

FsrsEngine::FsrsEngine(const Parameters &params)
    : m_params(params)
{
}

void FsrsEngine::setParameters(const Parameters &params)
{
    m_params = params;
}

// Core API.

FsrsEngine::MemoryState FsrsEngine::initMemory(int rating) const
{
    MemoryState ms;
    ms.stability = initStability(rating);
    ms.difficulty = clampDifficulty(initDifficulty(rating));
    return ms;
}

FsrsEngine::ReviewResult FsrsEngine::review(
    const MemoryState &current, int rating, double elapsed_days) const
{
    ReviewResult result;
    result.log.rating = rating;
    result.log.memory_before = current;
    result.log.elapsed_days = elapsed_days;

    if (current.stability <= 0.0) {
        // First review — init from rating
        result.memory = initMemory(rating);
    } else if (elapsed_days <= 0.0) {
        // Same-day review — short-term stability formula
        double stability = current.stability
                           * stabilityShortTerm(current, rating);
        result.memory = { stability, current.difficulty };
    } else {
        double R = forgettingCurve(current.stability, elapsed_days);
        result.log.retrievability = R;

        if (rating == 1) {
            // Again — failure path
            double stability = stabilityFail(current, R);
            // Difficulty unchanged on failure (per fsrs-rs model.rs)
            result.memory = { stability, current.difficulty };
        } else {
            // Hard / Good / Easy — success path
            double stability = current.stability
                               * stabilitySuccess(current, R, rating);
            double difficulty = nextDifficulty(current.difficulty, rating);
            result.memory = { stability, difficulty };
        }
    }

    result.log.memory_after = result.memory;
    result.log.scheduled_days = getInterval(result.memory.stability);

    return result;
}

double FsrsEngine::getRetrievability(double stability, double elapsed_days) const
{
    if (stability <= 0.0)
        return 1.0;
    return forgettingCurve(stability, elapsed_days);
}

double FsrsEngine::getInterval(double stability) const
{
    return getInterval(stability, m_params.desired_retention);
}

double FsrsEngine::getInterval(double stability,
                                double desired_retention) const
{
    if (stability <= 0.0)
        return 1.0;

    const double decay = -m_params.w[20];
    const double factor = forgetFactor();
    // I = S / factor * (r^(1/decay) - 1)
    // When r=0.9: r^(1/decay) = 0.9^(-1/w[20]) = factor + 1 → I=S ✓
    double interval = stability / factor
                      * (std::pow(desired_retention, 1.0 / decay) - 1.0);

    // Clamp to [1, max_interval]
    interval = std::max(1.0, std::min(interval,
                        static_cast<double>(m_params.max_interval)));

    return interval;
}

// Internal formula helpers.

double FsrsEngine::forgettingCurve(double stability, double elapsed_days) const
{
    // R(t,S) = (1 + factor·t/S)^(-w[20])
    // Reference: awesome-fsrs wiki, FSRS-6 section
    // model.rs: power_forgetting_curve()
    const double decay = -m_params.w[20];  // positive decay value
    const double factor = forgetFactor();

    const double arg = 1.0 + factor * elapsed_days / stability;
    return std::pow(arg, -m_params.w[20]); // = arg^(-w[20])
}

double FsrsEngine::forgetFactor() const
{
    // factor = 0.9^(-1/w[20]) - 1
    // such that R(S,S) = 0.9
    const double decay = -m_params.w[20];  // = -w[20] (positive)
    return std::exp(std::log(0.9) / decay) - 1.0;
}

double FsrsEngine::initStability(int rating) const
{
    // S₀(G) = w[G-1]   for G=1..4
    const int idx = std::clamp(rating - 1, 0, 3);
    return m_params.w[idx];
}

double FsrsEngine::initDifficulty(int rating) const
{
    // D₀(G) = w₄ - exp(w₅·(G-1)) + 1
    // Reference: awesome-fsrs wiki §4
    // model.rs: init_difficulty()
    const int g = std::clamp(rating - 1, 0, 3);
    return m_params.w[4] - std::exp(m_params.w[5] * g) + 1.0;
}

double FsrsEngine::stabilitySuccess(const MemoryState &current,
                                     double retrievability,
                                     int rating) const
{
    // S'_r(D,S,R,G) = S · (exp(w₈)·(11-D)·S^(-w₉)·(exp(w₁₀·(1-R))-1)
    //                       · w₁₅·w₁₆ + 1)
    // Reference: awesome-fsrs wiki §5, FSRS v4 formula (unchanged in FSRS-6)
    // model.rs: stability_success()
    const auto &w = m_params.w;

    const double hard_penalty = (rating == 2) ? w[15] : 1.0;
    const double easy_bonus   = (rating == 4) ? w[16] : 1.0;

    // exp(w₈)
    const double exp_factor = std::exp(w[8]);
    // (11 - D)
    const double d_factor = 11.0 - current.difficulty;
    // S^(-w₉)
    const double s_factor = std::pow(current.stability, -w[9]);
    // (exp(w₁₀·(1-R)) - 1)
    const double r_factor = std::exp(w[10] * (1.0 - retrievability)) - 1.0;

    const double SInc = exp_factor * d_factor * s_factor * r_factor
                        * hard_penalty * easy_bonus + 1.0;

    // SInc must be >= 1 for successful reviews
    return std::max(1.0, SInc);
}

double FsrsEngine::stabilityFail(const MemoryState &current,
                                  double retrievability) const
{
    // S'_f(D,S,R) = w₁₁ · D^(-w₁₂) · ((S+1)^(w₁₃)-1) · exp(w₁₄·(1-R))
    // Reference: awesome-fsrs wiki §6, FSRS v4 formula (unchanged in FSRS-6)
    // model.rs: stability_fail()
    const auto &w = m_params.w;

    const double d_factor = std::pow(current.difficulty, -w[12]);
    const double s_factor = std::pow(current.stability + 1.0, w[13]) - 1.0;
    const double r_factor = std::exp(w[14] * (1.0 - retrievability));

    double S_f = w[11] * d_factor * s_factor * r_factor;

    // Post-lapse stability must never exceed pre-lapse stability
    return std::min(S_f, current.stability);
}

double FsrsEngine::stabilityShortTerm(const MemoryState &current,
                                       int rating) const
{
    // S'(S,G) = S · exp(w₁₇·(G-3+w₁₈)) · S^(-w₁₉)
    // Reference: awesome-fsrs wiki §7, FSRS-6 specific
    // model.rs: stability_short_term()
    const auto &w = m_params.w;

    double SInc = std::exp(w[17] * (rating - 3.0 + w[18]))
                  * std::pow(current.stability, -w[19]);

    // Ensure SInc >= 1 when G >= 3 (successful same-day)
    if (rating >= 2)
        SInc = std::max(1.0, SInc);

    return SInc;
}

double FsrsEngine::nextDifficulty(double current_difficulty, int rating) const
{
    // D'(D,G) = D + (-w₆·(G-3)) · (10-D)/9
    // D'' = w₇·D₀(4) + (1-w₇)·D'
    // Reference: awesome-fsrs wiki §8, FSRS-5 formula (unchanged in FSRS-6)
    // model.rs: next_difficulty()
    const auto &w = m_params.w;

    // Step 1: grade delta
    const double delta_D = -w[6] * (rating - 3.0);

    // Step 2: linear damping (asymptotic approach to 10)
    const double D_damped = current_difficulty
                            + delta_D * (10.0 - current_difficulty) / 9.0;

    // Step 3: mean reversion toward D₀(4)
    const double D0_4 = clampDifficulty(initDifficulty(4));

    return clampDifficulty(w[7] * D0_4 + (1.0 - w[7]) * D_damped);
}
