import std.parallelism;
import std.range;
import std.stdio;

import ae.sys.datamm;
import ae.utils.meta;

import expand;
import graph;
import game;
import packing;

enum opponent = Opponent.game;

void main()
{
	auto scoreData = mapFile(scoreFileName(opponent), MmMode.read);
	auto scores = scoreData.asDataOf!PackedScore.unsafeContents;

	struct Driver
	{
		enum interactive = false;
		void log(scope string delegate() message) nothrow @nogc {}

		Score recurse(const ref Game game) nothrow @nogc
		{
			auto packedGame = game.packGame();
			return scores[packedGame].unpackScore;
		}

		alias gameOver = graphGameOver;

		bool topLevel = true;
		Score[enumLength!Move] moveScores;

		alias GetScore(T) = Score delegate(T) nothrow @nogc;
		Score choice(ChoiceMode mode, T)(
			scope string delegate() description,
			scope GetScore!T getScore,
			scope string delegate(T) getDescription,
			scope const(T)[] items...
		) {
			if (topLevel)
			{
				static if (mode == ChoiceMode.best && is(T == Move))
				{
					assert(items.length == enumLength!Move);

					{
						topLevel = false; scope(exit) topLevel = true;
						foreach (move; items)
							moveScores[move] = getScore(move);
					}

					return 0; // Result unused
				}
				else
					assert(false, "Expected the first choice to be a move choice");
			}
			else
			{
				alias gc = graphChoice!GetScore;
				return gc!(mode, T)(
					description,
					getScore,
					getDescription,
					items,
				);
			}
		}
	}

	PackedGame numDone;
	Score bestDelta = 0;
	foreach (packedGame; packedGameCard.iota.parallel)
	{
		enum progressPeriod = 0x1000000;
		if (packedGame % progressPeriod == 0)
			synchronized
			{
				numDone += progressPeriod;
				stderr.write(100 * numDone / packedGameCard, "%\r"); stderr.flush();
			}

		auto game = packedGame.unpackGame();
		if (game.currentTurn != Character.player)
			continue;
		if (game.totalShells == 0)
			continue;
		if (game.items[Character.dealer][Item.cigarettePack] > 2)
			continue;

		// Filter:
		if (game.totalItems(Character.player))
			continue;
		if (!game.nextShell.isNull)
			continue;

		auto driver = Driver();
		expand.expand(game, &driver, opponent);
		auto delta = driver.moveScores[Move.shootSelf] - driver.moveScores[Move.shootOther];
		if (delta > 0)
		{
			synchronized
			{
				if (delta >= bestDelta)
				{
					writefln("Game #%d: Shooting self is better than shooting opponent by %f%%",
						packedGame, (driver.moveScores[Move.shootSelf] - driver.moveScores[Move.shootOther]) * 100);
					bestDelta = delta;
				}
			}
		}
	}
}
