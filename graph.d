import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv;
import std.file;
import std.math.algebraic;
import std.math.rounding;
import std.parallelism;
import std.range;
import std.stdio : File, stderr;

import ae.sys.data;
import ae.sys.datamm;
import ae.sys.file : truncate, atomic, atomicExchange;
import ae.utils.meta;
import ae.utils.text;

import game;
import expand;
import packing;

struct PackedScore
{
	alias Value = ushort;
	Value value;
}

PackedScore packScore(Score score) nothrow @nogc
in(0 <= score && score <= 1)
{
	return PackedScore(cast(PackedScore.Value)round(score * PackedScore.Value.max));
}

Score unpackScore(PackedScore packed) nothrow @nogc
{
	return Score(packed.value) / PackedScore.Value.max;
}

unittest
{
	foreach (score; [0, 0.25, 0.5, 0.75, 1])
		assert(abs(score - score.packScore.unpackScore) < 1.0 / PackedScore.Value.max);
}

alias ScoreTable = PackedScore[/*packedGameCard*/];

string scoreFileName(Opponent opponent)
{
	return "data/scores-" ~ text(opponent) ~ ".i" ~ text(PackedScore.Value.sizeof * 8);
}

void propagateScores(const ScoreTable source, ScoreTable target, Opponent opponent)
{
	stderr.writeln("Copying...");
	{
		PackedGame numDone;
		foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
		{
			target[packedGame] = source[packedGame];
			enum progressPeriod = 0x1000000;
			if (packedGame % progressPeriod == 0)
				synchronized
				{
					numDone += progressPeriod;
					stderr.write(100 * numDone / packedGameCard, "%\r"); stderr.flush();
				}
		}
	}

	struct Driver
	{
		void log(scope string delegate() message) nothrow @nogc {}

		Score recurse(const ref Game game) nothrow @nogc
		{
			return source[game.packGame()].unpackScore;
		}

		alias choice = graphChoice;
	}
	auto driver = Driver();

	stderr.writeln("Expanding...");
	{
		PackedGame numDone;
		foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
		{
			auto game = packedGame.unpackGame();
			auto score = expand.expand(game, &driver, opponent);
			target[packedGame] = score.packScore;
			enum progressPeriod = 0x1000000;
			if (packedGame % progressPeriod == 0)
				synchronized
				{
					numDone += progressPeriod;
					stderr.write(100 * numDone / packedGameCard, "%\r"); stderr.flush();
				}
		}
	}
}

void generateScoreFile(Opponent opponent)
{
	import std.stdio : writeln;

	stderr.writeln("=== Generating scores for ", opponent);

	auto fn = scoreFileName(opponent);
	if (!fn.exists)
	{
		writeln("Initializing scores...");
		void createFile(string target)
		{
			File(target, "wb").truncate(packedGameCard * PackedScore.sizeof);
			mapFile(target, MmMode.readWrite)
				.asDataOf!PackedScore
				.enter((scope PackedScore[] scores) {
					//scores[] = scoreIndeterminate;
					foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
						scores[packedGame] = scoreIndeterminate.packScore;
				});
		}
		atomic!createFile(fn);
	}

	bool stop = false;
	for (size_t iter = 0; !stop; iter++)
	{
		writeln("Iteration #", iter);

		auto nextFn = fn ~ "-next";
		{
			auto currentData = mapFile(fn, MmMode.read).asDataOf!PackedScore;
			auto current = currentData.unsafeContents;

			File(nextFn, "ab").truncate(packedGameCard * PackedScore.sizeof);

			auto nextData = mapFile(nextFn, MmMode.readWrite).asDataOf!PackedScore;
			auto next = nextData.unsafeContents;

			propagateScores(current, next, opponent);

			auto totalChange = zip(current, next).map!(pair => abs(long(pair[0].value) - pair[1].value)).sum;
			auto maxChange = zip(current, next).map!(pair => abs(int(pair[0].value) - pair[1].value)).reduce!max;
			auto numChanged = zip(current, next).map!(pair => pair[0] == pair[1] ? 1L : 0L).sum;
			// auto crc = crc32Of(table);
			auto changeLimit = 1;
			writeln(" > Change: num=", numChanged, " / ", packedGameCard,
				", total=", totalChange,
				", avg=", (double(totalChange) / packedGameCard).fpToString,
				", max=", maxChange, " / ", changeLimit,
				// ", CRC=", crc[].format!"%(%02x%)",
			);

			if (maxChange <= changeLimit)
			// if (crc in sawCRC)
				stop = true;
			// sawCRC[crc] = true;
		}

		atomicExchange(fn, nextFn);
	}
	stderr.writeln("Change threshold reached.");
}

unittest
{
	if (false) generateScoreFile(Opponent.init);
}

version (main_graph)
void main()
{
	foreach (opponent; Opponent.init .. enumLength!Opponent)
		generateScoreFile(opponent);
}
