import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.conv;
import std.exception;
import std.file;
import std.math.traits;
import std.range;
import std.stdio;
import std.string;
import std.typecons;

import ae.net.ssl.openssl;
import ae.sys.datamm;
import ae.utils.array;
import ae.utils.json;
import ae.utils.meta;

import game;
import expand;
import graph;
import packing;
import remotegraph;

mixin SSLUseLib;

class JSGameError : Exception
{
	string[] badIDs;
	this(string msg, string[] badIDs)
	{
		this.badIDs = badIDs;
		super(msg);
	}
}

struct JSGame
{
	Character currentTurn;
	Nullable!ShellType[maxShells] shells;
	Nullable!ShellType nextShell; // includes a shell from `shells`, unlike `Game`
	Nullable!Item[maxItems][enumLength!Character] items;
	ubyte[enumLength!Character] health = [1, 1];
	Nullable!HandcuffState[enumLength!Character] handcuffs; // `null` <=> `HandcuffState.none`
	bool shotgunSawedOff;

	/// Convert `Game` to `JSGame`, trying to not move
	/// things around too much (compared to `reference`).
	this(const Game game, JSGame reference)
	{
		this = reference;

		this.nextShell = game.nextShell;
		foreach (shellType; ShellType.init .. enumLength!ShellType)
			while (this.toGame(false).shells[shellType] > game.shells[shellType])
				this.shells[this.shells[].lastIndexOf(shellType.nullable)] = Nullable!ShellType.init;
		foreach (shellType; ShellType.init .. enumLength!ShellType)
			while (this.toGame(false).shells[shellType] < game.shells[shellType])
				this.shells[this.shells[].indexOf(Nullable!ShellType.init)] = shellType.nullable;

		foreach (character; Character.init .. enumLength!Character)
		{
			foreach (item; Item.init .. enumLength!Item)
				while (this.toGame(false).items[character][item] > game.items[character][item])
					this.items[character][this.items[character][].lastIndexOf(item.nullable)] = Nullable!Item.init;
			foreach (item; Item.init .. enumLength!Item)
				while (this.toGame(false).items[character][item] < game.items[character][item])
					this.items[character][this.items[character][].indexOf(Nullable!Item.init)] = item.nullable;
		}

		foreach (character; Character.init .. enumLength!Character)
			this.health[character] = game.health[character];

		this.currentTurn = game.currentTurn;
		foreach (character; Character.init .. enumLength!Character)
			if (game.handcuffs[character] == HandcuffState.none)
				this.handcuffs[character] = Nullable!HandcuffState.init;
			else
				this.handcuffs[character] = game.handcuffs[character].HandcuffState.nullable;

		this.shotgunSawedOff = game.shotgunSawedOff;

		assert(this.toGame(false) == game);
	}

	Game toGame(bool strict = true) const
	{
		Game game;

		game.currentTurn = this.currentTurn;

		foreach (shell; this.shells)
			if (!shell.isNull)
				game.shells[shell.get()]++;
		game.nextShell = this.nextShell;
		if (!this.nextShell.isNull)
		{
			auto shellType = this.nextShell.get();
			if (strict && !game.shells[shellType])
				throw new JSGameError("Shells / next shell discrepancy.",
					maxShells.iota
					.map!(shellIndex => "shell-" ~ text(shellIndex))
					.array
					~ ["shell-next"]
				);
			game.shells[shellType]--;
		}
		foreach (shellType; ShellType.init .. enumLength!ShellType)
			if (strict && game.shells[shellType] > maxShells / 2)
				throw new JSGameError("Cannot have that many shells of one type.",
					maxShells.iota
					.filter!(shellIndex => this.shells[shellIndex] == shellType.nullable)
					.map!(shellIndex => "shell-" ~ text(shellIndex))
					.array
				);
		foreach (character; Character.init .. enumLength!Character)
		{
			foreach (item; this.items[character])
				if (!item.isNull)
					game.items[character][item.get()]++;
			if (strict && game.items[character][Item.cigarettePack] > 2)
				throw new JSGameError("Cannot have that many cigarette packs.",
					maxItems.iota
					.filter!(itemIndex => this.items[character][itemIndex] == Item.cigarettePack.nullable)
					.map!(itemIndex => "item-" ~ text(ubyte(character)) ~ "-" ~ text(itemIndex))
					.array
				);
		}
		foreach (character; Character.init .. enumLength!Character)
		{
			enforce(this.health[character] > 0 && this.health[character] <= 4);
			game.health[character] = this.health[character];
		}
		foreach (character; Character.init .. enumLength!Character)
			game.handcuffs[character] = this.handcuffs[character].get(HandcuffState.none);
		if (strict && game.handcuffs[Character.player] && game.handcuffs[Character.dealer])
			throw new JSGameError("Only one character may be handcuffed at a time.",
				["handcuffs-0", "handcuffs-1"]
			);
		if (strict && game.handcuffs[game.currentTurn])
			throw new JSGameError("A handcuffed player cannot have the current turn.",
				["handcuffs-" ~ text(ubyte(game.currentTurn)), "handle"]
			);
		game.shotgunSawedOff = this.shotgunSawedOff;
		return game;
	}
}

/// Index into the `items` array passed to some `Driver.choice` call
alias ItemIndex = size_t;

/// Index into some `JSAnalysis.Event.Choice.options` array.
alias OptionIndex = size_t;

struct JSProblem
{
	Opponent opponent;

	Nullable!JSGame game;
	// -- or --
	string packedGame;

	ItemIndex[] decisions;
}

struct JSAnalysis
{
	JSGame game;
	@JSONOptional string packedGame;

	struct Event
	{
		@JSONOptional string message;

		@JSONOptional Nullable!Score start;

		struct Recursion
		{
			JSGame game;
			string packedGame;
			Score score;
		}
		@JSONOptional Recursion recursion;

		struct Choice
		{
			string description;
			ChoiceMode mode;
			struct Option
			{
				/// All decisions up to this point including this one, starting with `game`.
				/// Put this in `JSProblem.decisions`.
				ItemIndex[] decisions;

				string description;
				Score outcome;

				/// Present only for non-uniform random choice events.
				@JSONOptional Nullable!double probability;
			}
			Option[] options;
			Score score; // According to the algorithm - NOT according to `selectedOptionIndex`.
			// If analysis continues, this shows across which branch it does so.
			@JSONOptional Nullable!OptionIndex selectedOptionIndex; // This one is an index into `options`.
		}
		@JSONOptional Choice choice;

		@JSONOptional Nullable!bool gameOver;
	}
	Event[] events;

	struct ValidationError
	{
		string message;
		string[] ids;
	}
	@JSONOptional ValidationError validationError;
}

struct Driver(Scores)
{
	const(JSProblem)* problem;
	Scores scores;
	JSAnalysis* analysis;

	// When true, we are doing linear descent.
	// When false, we are doing a regular recursive depth-first
	// search in order to calculate a score (win probability).
	bool interactive = true;

	JSGame[] recursedGames;
	ItemIndex[] decisions; // Decisions made since the very start; index into items

	void log(scope string delegate() message)
	{
		if (!interactive)
			return;

		JSAnalysis.Event event;
		event.message = message();
		analysis.events ~= event;
	}

	Score run(const ref Game game)
	{
		assert(interactive);

		JSAnalysis.Event event;
		size_t eventIndex = analysis.events.length;
		analysis.events ~= event;

		auto score = expand.expand(game, &this, problem.opponent);
		analysis.events[eventIndex].start = score;

		return score;
	}

	Score recurse(const ref Game game)
	{
		if (!interactive)
			return scores[game.packGame()].unpackScore;

		auto jsGame = JSGame(game, recursedGames[$-1]);
		recursedGames ~= jsGame;
		scope(exit) recursedGames = recursedGames[0 .. $-1];

		JSAnalysis.Event event;
		event.recursion = JSAnalysis.Event.Recursion(jsGame, game.packGame().to!string);
		size_t eventIndex = analysis.events.length;
		analysis.events ~= event;

		auto score = expand.expand(game, &this, problem.opponent);
		analysis.events[eventIndex].recursion.score = score;

		return score;
	}

	alias GetScore(T) = Score delegate(T);

	Score choice(T)(
		ChoiceMode mode,
		scope string delegate() description,
		scope Score delegate(T) getScore,
		scope string delegate(T) getDescription,
		scope const(T)[] items...
	) {
		if (!interactive)
		{
			alias gc = graphChoice!GetScore;
			return gc!T(
				mode,
				description,
				getScore,
				getDescription,
				items,
			);
		}

		// First, record the event.
		JSAnalysis.Event event;
		event.choice.description = description();
		event.choice.mode = mode;

		struct Option
		{
			T item;
			size_t count;
			ItemIndex itemIndex;
			Score score;
		}
		Option[] options;

		auto needDeduplication = mode == ChoiceMode.randomWithDuplicates;
		if (!needDeduplication)
		{
			options.length = items.length;
			foreach (i; 0 .. items.length)
				options[i] = Option(items[i], 1, i);
		}
		else
		{
			enum card = itemCardinality!T;
			static if (card)
			{
				size_t[card] counts;
				ItemIndex[card] itemIndices;
				foreach_reverse (ItemIndex itemIndex, T item; items)
				{
					counts[item.toCardinal()]++;
					itemIndices[item.toCardinal()] = itemIndex;
				}

				foreach (numericItem; 0 .. card)
				{
					auto item = numericItem.fromCardinal!T();
					auto count = counts[numericItem];
					if (!count)
						continue;

					options ~= Option(item, counts[numericItem], itemIndices[numericItem]);
				}
			}
			else
				assert(false);
		}

		foreach (ref option; options)
		{
			interactive = false; scope(exit) interactive = true;
			option.score = getScore(option.item);
		}

		foreach_reverse (optionIndex, ref option; options)
			if (option.score.isNaN)
				options = options.remove(optionIndex);

		auto includeProbabilities = mode == ChoiceMode.randomWithDuplicates;

		foreach (ref option; options)
		{
			assert(option.count);
			auto jsOption = JSAnalysis.Event.Choice.Option(
				decisions ~ option.itemIndex,
				getDescription(option.item),
				option.score,
			);
			if (includeProbabilities)
				jsOption.probability = 1.0 * option.count / items.length;
			event.choice.options ~= jsOption;
		}

		Nullable!OptionIndex selectedOptionIndex;
		Score score = {
			final switch (mode)
			{
				case ChoiceMode.random:
				case ChoiceMode.randomWithDuplicates:
					Score sum = 0;
					size_t total = 0;
					foreach (ref option; options)
						if (!option.score.isNaN)
						{
							sum += option.score * option.count;
							total += option.count;
						}
					return sum / total;

				case ChoiceMode.best:
					Score bestScore = -Score.max;
					foreach (OptionIndex optionIndex, ref option; options)
						if (option.score > bestScore) // Comparison with NaN will yield false
						{
							bestScore = option.score;
							selectedOptionIndex = optionIndex;
						}
					assert(bestScore != -Score.max, "All choices are invalid");
					return bestScore;

				case ChoiceMode.worst:
				case ChoiceMode.unknown:
					Score worstScore = Score.max;
					foreach (OptionIndex optionIndex, ref option; options)
						if (option.score < worstScore) // Comparison with NaN will yield false
						{
							worstScore = option.score;
							selectedOptionIndex = optionIndex;
						}
					assert(worstScore != Score.max, "All choices are invalid");
					return worstScore;
			}
		}();
		event.choice.score = score;

		if (selectedOptionIndex.isNull && options.length == 1)
			selectedOptionIndex = 0;

		if (decisions.length < problem.decisions.length)
		{
			// User's decision overrides what the algorithm would choose.
			auto itemIndex = problem.decisions[decisions.length];
			enforce(itemIndex < items.length, "Invalid choice index");
			auto optionIndex = options.countUntil!((ref option) => option.itemIndex == itemIndex);
			enforce(optionIndex >= 0, "Item is not an option");
			selectedOptionIndex = optionIndex;
		}

		event.choice.selectedOptionIndex = selectedOptionIndex;
		analysis.events ~= event;

		// Move forward when the graph expansion algorithm does so:
		if (!selectedOptionIndex.isNull)
		{
			auto itemIndex = options[selectedOptionIndex.get()].itemIndex;
			decisions ~= itemIndex; scope(exit) decisions = decisions[0 .. $-1];
			auto userChoiceScore = getScore(items[itemIndex]);
			// Discard user choice score (do not let scores bubble up).
			cast(void) userChoiceScore;
		}

		return score;
	}

	Score gameOver(bool playerWon)
	{
		if (!interactive)
			return graphGameOver(playerWon);

		JSAnalysis.Event event;
		event.gameOver = playerWon;
		analysis.events ~= event;

		return graphGameOver(playerWon);
	}
}

JSAnalysis analyze(Scores)(JSProblem problem, Scores scores)
{
	JSAnalysis analysis;
	try
	{

		JSGame jsGame = {
			if (!problem.game.isNull) return problem.game.get;
			if (problem.packedGame) return problem.packedGame.to!PackedGame.unpackGame().JSGame(JSGame.init);
			throw new Exception("No game");
		}();
		analysis.game = jsGame;

		Game game;
		if (problem.packedGame)
			game = problem.packedGame.to!PackedGame.unpackGame();
		else
			game = problem.game.get().toGame();
		analysis.packedGame = game.packGame().to!string;

		Driver!Scores driver;
		driver.problem = &problem;
		driver.scores = scores;
		driver.analysis = &analysis;
		driver.recursedGames = [jsGame];

		driver.run(game);
	}
	catch (JSGameError e)
		analysis.validationError = JSAnalysis.ValidationError(e.msg, e.badIDs);
	return analysis;
}

void main(string[] args)
{
	bool local = true;

	try
	{
		enforce(args.length == 2, "Bad usage");
		auto problem = args[1].jsonParse!JSProblem;

		JSAnalysis analysis;
		if (local)
		{
			auto scoreData = mapFile(scoreFileName(problem.opponent), MmMode.read);
			auto scores = scoreData.asDataOf!PackedScore.unsafeContents;

			analysis = analyze(problem, scores);
		}
		else
		{
			auto scores = new RemoteScores(problem.opponent);
			do
				analysis = analyze(problem, scores);
			while (!scores.resolve());
		}

		stdout.writeln(analysis.toJson.replace("nan", "null"));
	}
	catch (Exception e)
	{
		struct ErrorReply { string error; }
		stdout.writeln(ErrorReply(e.msg).toJson);
		return;
	}
}
