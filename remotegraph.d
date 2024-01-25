import std.algorithm.sorting;
import std.conv;
import std.exception;
import std.file;
import std.path;

import ae.net.asockets;
import ae.net.http.client;
import ae.utils.aa;
import ae.utils.array;
import ae.sys.dataset;

import expand : Opponent, scoreIndeterminate;
import graph : scoreFileName, PackedScore, packScore;
import packing : PackedGame;

final class RemoteScores
{
private:
	PackedScore[PackedGame] resolved;
	HashSet!PackedGame todo;
	string url;

public:
	this(Opponent opponent)
	{
		url = "~/.config/buckshot-roulette-data".expandTilde().readText()
			~ scoreFileName(opponent).baseName;
	}

	PackedScore opIndex(PackedGame game)
	{
		if (auto p_score = game in resolved)
			return *p_score;
		todo.add(game);
		return scoreIndeterminate.packScore; // placeholder value
	}

	// Returns true if resolution succeeded entirely;
	// false, if a rerun is needed.
	bool resolve()
	{
		if (todo.empty)
			return true;

		auto games = todo.keys.sort.release;
		todo = null;

		auto client = new HttpsClient;
		client.keepAlive = true;
		client.pipelining = true;
		client.agent = null;
		client.handleResponse = (HttpResponse response, string disconnectReason) {
			enforce(response, disconnectReason);
			enforce(response.data.bytes.length == PackedScore.sizeof, "Bad payload size");
			PackedScore score;
			response.data.copyTo(score.asSlice.asBytes);
			resolved.addNew(games.shift(), score).enforce();
			if (!games.length)
				client.disconnect();
		};
		foreach (game; games)
		{
			auto request = new HttpRequest(url);
			request.headers["Range"] = "bytes=" ~ text(game * PackedScore.sizeof) ~ "-" ~ text(game * PackedScore.sizeof + PackedScore.sizeof - 1);
			client.request(request);
		}

		socketManager.loop();

		assert(!games.length);

		return false;
	}
}

// Debug helper (assert/invariant guard)
bool scoresAreFinal(Scores)(Scores scores)
{
	static if (is(Scores == RemoteScores))
		return scores.todo.byKey.empty;
	else
		return true;
}
