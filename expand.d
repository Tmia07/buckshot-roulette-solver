import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv : to;
import std.stdio;
import std.traits;
import std.typecons;

import ae.utils.meta;

import game;

enum Move : ubyte
{
	shootSelf,
	shootOther,
	useLookingGlass,
	useHandcuffs,
	useBeer,
	useCigarettePack,
	useHandSaw,
}

string[enumLength!Item] itemDescriptions = [
	"a Looking Glass",
	"Handcuffs",
	"a Beer",
	"a Cigarette Pack",
	"a Hand Saw",
];

string getMoveDescription(Move move, Character who)
{
	final switch (move)
	{
		case Move.shootSelf       : return who == Character.player ? "Shoot yourself" : "Shoot themselves";
		case Move.shootOther      : return who == Character.player ? "Shoot you" : "Shoot the dealer";
		case Move.useLookingGlass : return "Use a Looking Glass";
		case Move.useHandcuffs    : return "Use Handcuffs";
		case Move.useBeer         : return "Use a Beer";
		case Move.useCigarettePack: return "Use a Cigarette Pack";
		case Move.useHandSaw      : return "Use a Hand Saw";
	}
}

alias Score = double;

/// For `Driver.choice`
enum ChoiceMode
{
	/// Something the game would choose at random.
	random,
	/// Something the player decides,
	/// so we should pick the best option for the player.
	best,
	/// Something the game decides in an unpredictable way,
	/// so we should pick the worst option for the player.
	worst,
}

Score expand(Driver)(const ref Game game, Driver driver)
{
	void switchTurn(ref Game game)
	{
		game.currentTurn = game.currentTurn.other;
		driver.log(() => "It is now " ~ (game.currentTurn == Character.player ? "your" : "the dealer's") ~ " turn.");
		if (game.handcuffs[game.currentTurn] == HandcuffState.willBreak)
		{
			driver.log(() => (game.currentTurn == Character.player ? "Your" : "The dealer's") ~ " handcuffs break off.");
			game.handcuffs[game.currentTurn] = HandcuffState.none;
		}
	}

	Score resolveRound(Dg)(const ref Game game, scope /* Score delegate(ShellType shellType, ref Game newGame) nothrow @nogc */ Dg handler)
	{
		if (!game.nextShell.isNull)
		{
			Game newGame = game;
			auto shellType = newGame.nextShell.get();
			newGame.nextShell.nullify();
			return handler(shellType, newGame);
		}
		
		ShellType[maxShells] shells;
		size_t numShells;
		foreach (shellType; ShellType.init .. enumLength!ShellType)
			foreach (i; 0 .. game.shells[shellType])
				shells[numShells++] = shellType;

		return driver.choice!ShellType(
			ChoiceMode.random,
			"What shell is next?",
			(shellType) {
				Game newGame = game;
				newGame.shells[shellType]--;
				return handler(shellType, newGame);
			},
			shellType => ["Blank", "Live"][shellType],
			shells[0 .. numShells]
		);
	}

	Score shoot(Character whom)
	{
		driver.log(() => 
			game.currentTurn == Character.player
			? whom           == Character.player
			? "You shoot yourself."
			: "You shoot the dealer."
			: whom           == Character.player
			? "The dealer shoots you."
			: "The dealer shoots themselves."
		);
		return resolveRound(game, (ShellType shellType, ref Game newGame) {
			auto damage = 1;
			if (newGame.shotgunSawedOff)
				damage = 2;
			final switch (shellType)
			{
				case ShellType.blank:
					driver.log(() => "Blank. No damage.");
					// If the shotgun was aimed at the other player, switch turns
					if (whom != newGame.currentTurn)
						switchTurn(newGame);
					break;
				case ShellType.live:
					driver.log(() => (whom == Character.player ? "You take" : "The dealer takes") ~ " " ~ damage.to!string ~ " damage.");
					newGame.health[whom] -= damage;
					if (newGame.health[whom] <= 0)
						final switch (whom)
						{
							case Character.player:
								driver.log(() => "You are out. You lose!");
								return 0;
							case Character.dealer:
								driver.log(() => "The dealer is out. You win!");
								return 1;
						}
					switchTurn(newGame);
					break;
			}
			if (newGame.shotgunSawedOff)
			{
				driver.log(() => "The shotgun barrel reapparates.");
				newGame.shotgunSawedOff = false;
			}
			return driver.recurse(newGame);
		});
	}

	Score use(Item item)
	{
		if (!game.items[game.currentTurn][item])
			return Score.nan;
		driver.log(() => (game.currentTurn == Character.player ? "You use " : "The dealer uses ") ~ itemDescriptions[item] ~ ".");
		Game newGame = game;
		newGame.items[game.currentTurn][item]--;
		final switch (item)
		{
			case Item.handcuffs:
				if (newGame.handcuffs[newGame.currentTurn.other])
					return Score.nan;
				newGame.handcuffs[newGame.currentTurn.other] = HandcuffState.willSkip;
				driver.log(() => (newGame.currentTurn.other == Character.player ? "You are" : "The dealer is") ~ " now handcuffed.");
				return driver.recurse(newGame);
			case Item.lookingGlass:
				if (!newGame.nextShell.isNull)
					return Score.nan;
				return resolveRound(newGame, (ShellType shellType, ref Game newGame) {
					driver.log(() => (newGame.currentTurn == Character.player ? "You now know" : "The dealer now knows") ~ " that the next shell is " ~ shellType.to!string ~ ".");
					newGame.nextShell = shellType;
					return driver.recurse(newGame);
				});
			case Item.beer:
				return resolveRound(newGame, (ShellType shellType, ref Game newGame) {
					driver.log(() => (newGame.currentTurn == Character.player ? "You rack" : "The dealer racks") ~ " the shotgun, and a " ~ shellType.to!string ~ " shell is ejected.");
					return driver.recurse(newGame);
				});
			case Item.cigarettePack:
				if (newGame.health[game.currentTurn] < maxHealth)
				{
					driver.log(() => (newGame.currentTurn == Character.player ? "You restore" : "The dealer restores") ~ " one charge.");
					newGame.health[game.currentTurn]++;
				}
				else
					driver.log(() => (newGame.currentTurn == Character.player ? "You are" : "The dealer is") ~ " already at maximum charges.");
				return driver.recurse(newGame);
			case Item.handSaw:
				if (newGame.shotgunSawedOff)
					return Score.nan;
				newGame.shotgunSawedOff = true;
				driver.log(() => "The shotgun barrel is now sawed off.");
				return driver.recurse(newGame);
		}
	}

	Score tryMove(Move move)
	{
		final switch (move)
		{
			case Move.shootSelf : return shoot(game.currentTurn);
			case Move.shootOther: return shoot(game.currentTurn.other);
			case Move.useLookingGlass: return use(Item.lookingGlass);
			case Move.useHandcuffs: return use(Item.handcuffs);
			case Move.useBeer: return use(Item.beer);
			case Move.useCigarettePack: return use(Item.cigarettePack);
			case Move.useHandSaw: return use(Item.handSaw);
		}
	}

	if (game.totalShells == 0)
	{
		// End of round.
		driver.log(() => "Starting new round.");
		// Refill magazine. TODO: better distribution, or even iterate?
		Game newGame = game;
		newGame.shells[] = 2;
		// Handcuffs come off. How will you grab the items otherwise?
		newGame.handcuffs[] = HandcuffState.none;
		// Give some items. Random distribution would probably be too slow.
		foreach (character; Character.init .. enumLength!Character)
			newGame.items[character][Item.lookingGlass]++;
		// It's always the player's turn first.
		newGame.currentTurn = Character.player;
		return driver.recurse(newGame);
	}

	if (game.handcuffs[game.currentTurn] == HandcuffState.willSkip)
	{
		driver.log(() => game.currentTurn == Character.player
			? "You are handcuffed and skip your turn."
			: "The dealer is handcuffed and skips their turn."
		);
		Game newGame = game;
		newGame.handcuffs[game.currentTurn] = HandcuffState.willBreak;
		switchTurn(newGame);
		return driver.recurse(newGame);
	}

	final switch (game.currentTurn)
	{
		case Character.player:
			// Assume that the player will proceed according to what's best for them.
			return driver.choice!Move(
				ChoiceMode.best,
				"What will you do?",
				&tryMove,
				move => getMoveDescription(move, Character.player),
				EnumMembers!Move,
			);

		case Character.dealer:
			static if (false)
			{
				// Assume that the dealer will proceed according to what's worst for the player.
				auto worstResult = SearchResult(Score.infinity);
				foreach (move; Move.init .. enumLength!Move)
				{
					auto score = tryMove(move);
					if (score < worstResult.score)
						worstResult = SearchResult(score, move);
				}
				return worstResult;
			}
			else
			{
				Score coinFlip(T)(
					scope Score delegate(T) getScore,
					scope string delegate(T) getDescription,
					scope T[] items...
				)
				{
					assert(items.length == 2);
					return driver.choice!T(
						ChoiceMode.random,
						"The dealer flips a coin...",
						getScore,
						item => (item == items[0] ? "Heads" : "Tails") ~ ": " ~ getDescription(item),
						items
					);
				}
					

				// Simulate game AI
				Nullable!Character dealerTarget;
				Nullable!ShellType knownShell;
				bool dealerKnowsShell;

				if (!game.nextShell.isNull)
				{
					// If it's resolved, it's guaranteed that the current character knows it
					knownShell = game.nextShell;
					dealerTarget = knownShell.get() == ShellType.live
						? Character.player
						: Character.dealer;
					dealerKnowsShell = true;
				}

				if (game.totalShells == 1)
				{
					knownShell = game.shells[ShellType.live]
						? ShellType.live
						: ShellType.blank;
					dealerTarget = knownShell.get() == ShellType.live
						? Character.player
						: Character.dealer;
					dealerKnowsShell = true;
				}

				// The real AI actually iterates over items using a hidden internal order
				// (order that items were acquired).
				// To be safe, assume an order which is most inconvenient for us.
				Move[enumLength!Item] itemOptions; size_t numItemOptions;
				if (game.items[game.currentTurn][Item.lookingGlass] && !dealerKnowsShell && game.totalShells != 1)
					itemOptions[numItemOptions++] = Move.useLookingGlass;
				if (game.items[game.currentTurn][Item.cigarettePack] && game.health[game.currentTurn] < maxHealth)
					itemOptions[numItemOptions++] = Move.useCigarettePack;
				if (game.items[game.currentTurn][Item.beer] && knownShell != ShellType.live.nullable && game.totalShells != 1)
					itemOptions[numItemOptions++] = Move.useBeer;
				if (game.items[game.currentTurn][Item.handcuffs] && game.handcuffs[game.currentTurn.other] == HandcuffState.none && game.totalShells != 1)
					itemOptions[numItemOptions++] = Move.useHandcuffs;
				if (game.items[game.currentTurn][Item.handSaw] && !game.shotgunSawedOff && knownShell == ShellType.live.nullable)
					itemOptions[numItemOptions++] = Move.useHandSaw;
				if (numItemOptions)
					return driver.choice!Move(
						ChoiceMode.worst,
						"The dealer will use an item...",
						&tryMove,
						move => getMoveDescription(move, Character.dealer),
						itemOptions[0 .. numItemOptions]
					);

				if (game.items[game.currentTurn][Item.handSaw] && !game.shotgunSawedOff && knownShell != nullable(ShellType.blank))
					return coinFlip!Move(
						&tryMove,
						move => getMoveDescription(move, Character.dealer),
						Move.shootSelf, Move.useHandSaw,
					);

				if (dealerTarget.isNull)
					return coinFlip!Move(
						&tryMove,
						move => getMoveDescription(move, Character.dealer),
						Move.shootSelf, Move.shootOther,
					);
				else
				{
					auto move = dealerTarget.get() == Character.dealer ? Move.shootSelf : Move.shootOther;
					return tryMove(move);
				}
			}
	}
}

nothrow @nogc
unittest
{
	static struct TestDriver
	{
		/// Make a note.
		void log(scope string delegate() message) nothrow @nogc {}

		/// Recursive search.
		/// Get the score of another game state,
		/// as if we descended recursively into it.
		Score recurse(const ref Game game) nothrow @nogc { assert(false); }

		/// A choice is happening.
		/// Filter out NaNs!
		Score choice(T)(
			ChoiceMode mode,
			lazy string description,
			scope Score delegate(T) getScore,
			scope string delegate(T) getDescription,
			scope T[] items...
		) { assert(false); }
	}

	Game game;
	TestDriver driver;
	if (false)
		expand(game, driver);
}

enum maxHealth = 3; // depends on current act
