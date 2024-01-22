import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv;
import std.file;
import std.math.algebraic;
import std.parallelism;
import std.range;
import std.stdio : File, stderr;

import ae.sys.data;
import ae.sys.datamm;
import ae.sys.file : truncate, atomic;
import ae.utils.meta;
import ae.utils.text;

import game;
import expand;
import packing;

alias ScoreTable = Score[/*packedGameCard*/];

string scoreFileName(Opponent opponent)
{
	return "data/scores-" ~ text(opponent) ~ ".f32";
}

void propagateScores(const ScoreTable source, ScoreTable target, Opponent opponent)
{
	stderr.writeln("Copying...");
	foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
		target[packedGame] = source[packedGame];

	struct Driver
	{
		void log(scope string delegate() message) nothrow @nogc {}

		Score recurse(const ref Game game) nothrow @nogc
		{
			return source[game.packGame()];
		}

		alias choice = graphChoice;
	}
	auto driver = Driver();

	stderr.writeln("Expanding...");
	foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
	{
		auto game = packedGame.unpackGame();
		auto score = expand.expand(game, &driver, opponent);
		target[packedGame] = score;
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
			File(target, "wb").truncate(packedGameCard * Score.sizeof);
			mapFile(target, MmMode.readWrite)
				.asDataOf!Score
				.enter((scope Score[] scores) {
					//scores[] = scoreIndeterminate;
					foreach (packedGame; packedGameCard.iota.parallel(packedGameCard / totalCPUs / 128))
						scores[packedGame] = scoreIndeterminate;
				});
		}
		atomic!createFile(fn);
	}

	for (size_t iter = 0; ; iter++)
	{
		writeln("Iteration #", iter);

		auto currentData = mapFile(fn, MmMode.read).asDataOf!Score;
		auto current = currentData.unsafeContents;

		auto nextFn = fn ~ "-next";
		File(nextFn, "wb").truncate(packedGameCard * Score.sizeof);

		auto nextData = mapFile(nextFn, MmMode.readWrite).asDataOf!Score;
		auto next = nextData.unsafeContents;

		propagateScores(current, next, opponent);

		auto totalChange = zip(current, next).map!(pair => abs(double(pair[0]) - pair[1])).sum;
		auto maxChange = zip(current, next).map!(pair => abs(double(pair[0]) - pair[1])).reduce!max;
		auto numChanged = zip(current, next).map!(pair => pair[0] == pair[1] ? 1L : 0L).sum;
		// auto crc = crc32Of(table);
		auto changeLimit = 1.0 / (2 ^^ (Score.mant_dig - 2)); // Calculate up to 22 bits of precision
		writeln(" > Change: num=", numChanged, " / ", packedGameCard,
			", total=", totalChange.fpToString,
			", avg=", (totalChange / packedGameCard).fpToString,
			", max=", maxChange.fpToString, " / ", changeLimit.fpToString,
			// ", CRC=", crc[].format!"%(%02x%)",
		);

		if (maxChange <= changeLimit)
		// if (crc in sawCRC)
			break;
		// sawCRC[crc] = true;
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
