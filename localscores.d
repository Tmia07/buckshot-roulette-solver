module localscores;

import core.time : MonoTime, Duration, seconds;
import std.algorithm.comparison : clamp;
import std.math.traits : isNaN;

import ae.utils.meta;

import game;
import expand;
import graph;
import packing;

/// Thrown when the search runs out of its time / memory budget.
class SearchBudgetExceeded : Exception
{
	this() { super("Search budget exceeded"); }
}

/// On-demand score calculator, used when no precomputed
/// `data/scores-*.i16` table is available.
/// (With 9 item types the full table would be ~10^14 entries,
/// so it cannot realistically be generated.)
///
/// Within a round the state graph is acyclic (every move consumes a shell
/// or an item), so it can be solved with memoization. Because big positions
/// have far too many states, the search is depth-limited: states deeper than
/// `maxDepth` actions are estimated from health. The caller increases
/// `maxDepth` step by step (iterative deepening) until the result is exact
/// or the time budget runs out.
/// The start of a new round is always estimated from the characters' health.
final class LocalScores
{
	Opponent opponent;

	/// Maximum number of actions to look ahead.
	uint maxDepth = uint.max;
	/// Abort the search (throw `SearchBudgetExceeded`) after this moment.
	MonoTime deadline = MonoTime.max;
	/// Abort the search if the memo grows past this many states.
	size_t maxStates = 4_000_000;

	/// Number of times the depth limit was hit (0 = result exact within the round).
	size_t cutoffs;

	private struct Entry
	{
		PackedScore score;
		uint depth;  // remaining depth the score was computed with
		bool exact;  // no depth cutoff in the subtree
	}
	private Entry[PackedGame] memo;
	private uint remaining;
	private uint calls;

	this(Opponent opponent) { this.opponent = opponent; }

	/// Prepare for a new search with the given depth limit.
	void reset(uint maxDepth)
	{
		this.maxDepth = maxDepth;
		this.remaining = maxDepth;
		this.cutoffs = 0;
	}

	static struct LocalDriver
	{
		LocalScores scores;
		bool interactive = false;
		void log(scope string delegate() message) {}
		Score recurse(const ref Game game) { return scores[game.packGame()].unpackScore; }
		alias GetScore(T) = Score delegate(T);
		alias choice = graphChoice!GetScore;
		alias gameOver = graphGameOver;
	}

	static bool isRoundStart(const ref Game game)
	{
		return game.totalShells == 0
			&& game.handcuffs[Character.player] == HandcuffState.none
			&& game.handcuffs[Character.dealer] == HandcuffState.none
			&& game.currentTurn == Character.player;
	}

	static Score healthEstimate(const ref Game game)
	{
		Score p = game.health[Character.player];
		Score d = game.health[Character.dealer];
		return p / (p + d);
	}

	PackedScore opIndex(PackedGame packedGame)
	{
		if (auto p = packedGame in memo)
			if (p.exact || p.depth >= remaining)
			{
				if (!p.exact)
					cutoffs++;
				return p.score;
			}

		if ((++calls & 0x3FF) == 0)
			if (MonoTime.currTime > deadline || memo.length > maxStates)
				throw new SearchBudgetExceeded();

		auto game = packedGame.unpackGame();
		Score score;
		bool exact = true;
		if (isRoundStart(game))
			score = healthEstimate(game);
		else
		if (remaining == 0)
		{
			score = healthEstimate(game);
			exact = false;
			cutoffs++;
		}
		else
		{
			// guard against cycles
			memo[packedGame] = Entry(scoreIndeterminate.packScore, remaining, false);
			auto cutoffsBefore = cutoffs;
			remaining--;
			scope(exit) remaining++;
			auto driver = LocalDriver(this);
			score = expand.expand(game, &driver, opponent);
			exact = cutoffs == cutoffsBefore;
		}
		if (score.isNaN)
			score = scoreIndeterminate;
		score = score.clamp(scoreLose, scoreWin);
		auto packed = score.packScore;
		memo[packedGame] = Entry(packed, remaining, exact);
		return packed;
	}
}
