import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv : to;
import std.math.traits;
import std.stdio;
import std.string : capitalize;
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
enum Score scoreLose = 0;
enum Score scoreWin = 1;
enum Score scoreIndeterminate = (scoreLose + scoreWin) / 2;

/// For `Driver.choice`
enum ChoiceMode
{
	/// Something the game would choose at random.
	/// All odds are equal.
	random,
	/// Same as "random", but the items can contain duplicates,
	/// to represent a biased choice.
	randomWithDuplicates,
	/// Something the player decides,
	/// so we should pick the best option for the player.
	best,
	/// Something a hypothetical perfect opponent would choose.
	worst,
	/// Something the game decides in an unpredictable way.
	/// For calculating the win chance, we treat this
	/// in the same way as "worst", to be safe.
	unknown,
}

enum Opponent
{
	game,
	perfect,
}

Score expand(Driver)(const ref Game game, Driver driver, Opponent opponent)
{
	struct State
	{
		Game game;
		alias game this;

		// Things that should be in the state (`Game`) but aren't
		// (because it's relatively inconsequential and will increase the state space too much):

		/// Upper and lower bound, inclusive, of what the initial health is
		/// (which is also the health that a character can heal up to).
		ubyte initialHealthMin = 2, initialHealthMax = 4;
	}

	Score resolveCanHealTo(Dg)(const ref State state0, ubyte targetHealth, scope /*Score delegate(State newState, bool result) nothrow @nogc*/ Dg handler)
	{
		State state1 = state0;
		state1.initialHealthMin = state1.initialHealthMin.max(state1.health[].fold!max(ubyte(0)));

		if (targetHealth > state1.initialHealthMax)
			return handler(state1, false);
		else
		if (targetHealth <= state1.initialHealthMax)
			return handler(state1, true);
		else
			return driver.choice!bool(
				ChoiceMode.unknown,
				() => "Is it possible to have " ~ targetHealth.to!string ~ " charges?",
				(result) {
					auto state2 = state1;
					if (result)
						state2.initialHealthMin = targetHealth;
					else
						state2.initialHealthMax = cast(ubyte)(targetHealth - 1);
					return handler(state2, result);
				},
				result => result ? "Yes" : "No",
				false, true,
			);
	}

	void switchTurn(ref State state)
	{
		state.currentTurn = state.currentTurn.other;
		driver.log(() => "It is now " ~ (state.currentTurn == Character.player ? "your" : "the dealer's") ~ " turn.");
		if (state.handcuffs[state.currentTurn] == HandcuffState.willBreak)
		{
			driver.log(() => (state.currentTurn == Character.player ? "Your" : "The dealer's") ~ " handcuffs break off.");
			state.handcuffs[state.currentTurn] = HandcuffState.none;
		}
	}

	Score resolveRound(Dg)(const ref State state, scope /* Score delegate(ShellType shellType, ref State newState) nothrow @nogc */ Dg handler)
	{
		if (!state.nextShell.isNull)
		{
			State newState = state;
			auto shellType = newState.nextShell.get();
			newState.nextShell.nullify();
			return handler(shellType, newState);
		}

		ShellType[maxShells] shells;
		size_t numShells;
		foreach (shellType; ShellType.init .. enumLength!ShellType)
			foreach (i; 0 .. state.shells[shellType])
				shells[numShells++] = shellType;

		return driver.choice!ShellType(
			ChoiceMode.randomWithDuplicates,
			() => "What shell is next?",
			(shellType) {
				State newState = state;
				newState.shells[shellType]--;
				return handler(shellType, newState);
			},
			shellType => ["Blank", "Live"][shellType],
			shells[0 .. numShells]
		);
	}

	Score shoot(ref const State state, Character whom)
	{
		driver.log(() => 
			state.currentTurn == Character.player
			? whom            == Character.player
			? "You shoot yourself."
			: "You shoot the dealer."
			: whom            == Character.player
			? "The dealer shoots you."
			: "The dealer shoots themselves."
		);
		return resolveRound(state, (ShellType shellType, ref State newState) {
			auto damage = 1;
			if (newState.shotgunSawedOff)
				damage = 2;
			final switch (shellType)
			{
				case ShellType.blank:
					driver.log(() => "Blank. No damage.");
					// If the shotgun was aimed at the other player, switch turns
					if (whom != newState.currentTurn)
						switchTurn(newState);
					break;
				case ShellType.live:
					driver.log(() => (whom == Character.player ? "You take" : "The dealer takes") ~ " " ~ damage.to!string ~ " damage.");
					newState.health[whom] -= damage;
					if (newState.health[whom] <= 0)
						final switch (whom)
						{
							case Character.player:
								driver.log(() => "You are out. You lose!");
								return scoreLose;
							case Character.dealer:
								driver.log(() => "The dealer is out. You win!");
								return scoreWin;
						}
					switchTurn(newState);
					break;
			}
			if (newState.shotgunSawedOff)
			{
				driver.log(() => "The shotgun barrel reapparates.");
				newState.shotgunSawedOff = false;
			}
			return driver.recurse(newState);
		});
	}

	Score use(ref const State state, Item item)
	{
		if (!state.items[state.currentTurn][item])
			return Score.nan;
		driver.log(() => (state.currentTurn == Character.player ? "You use " : "The dealer uses ") ~ itemDescriptions[item] ~ ".");
		State newState = state;
		newState.items[state.currentTurn][item]--;
		final switch (item)
		{
			case Item.handcuffs:
				if (newState.handcuffs[newState.currentTurn.other])
					return Score.nan;
				newState.handcuffs[newState.currentTurn.other] = HandcuffState.willSkip;
				driver.log(() => (newState.currentTurn.other == Character.player ? "You are" : "The dealer is") ~ " now handcuffed.");
				return driver.recurse(newState);
			case Item.lookingGlass:
				if (!newState.nextShell.isNull)
					return Score.nan;
				return resolveRound(newState, (ShellType shellType, ref State newState) {
					driver.log(() => (newState.currentTurn == Character.player ? "You now know" : "The dealer now knows") ~ " that the next shell is " ~ shellType.to!string ~ ".");
					newState.nextShell = shellType;
					return driver.recurse(newState);
				});
			case Item.beer:
				return resolveRound(newState, (ShellType shellType, ref State newState) {
					driver.log(() => (newState.currentTurn == Character.player ? "You rack" : "The dealer racks") ~ " the shotgun, and a " ~ shellType.to!string ~ " shell is ejected.");
					return driver.recurse(newState);
				});
			case Item.cigarettePack:
				Score smoke(bool canHeal)
				{
					if (canHeal)
					{
						driver.log(() => (newState.currentTurn == Character.player ? "You restore" : "The dealer restores") ~ " one charge.");
						newState.health[state.currentTurn]++;
					}
					else
						driver.log(() => (newState.currentTurn == Character.player ? "You are" : "The dealer is") ~ " already at maximum charges.");
					return driver.recurse(newState);
				}
				return resolveCanHealTo(state, cast(ubyte)(newState.health[state.currentTurn] + 1),
					(State newState, bool result) { return smoke(result); });
			case Item.handSaw:
				if (newState.shotgunSawedOff)
					return Score.nan;
				newState.shotgunSawedOff = true;
				driver.log(() => "The shotgun barrel is now sawed off.");
				return driver.recurse(newState);
		}
	}

	Score tryMove(ref const State state, Move move)
	{
		final switch (move)
		{
			case Move.shootSelf : return shoot(state, state.currentTurn);
			case Move.shootOther: return shoot(state, state.currentTurn.other);
			case Move.useLookingGlass: return use(state, Item.lookingGlass);
			case Move.useHandcuffs: return use(state, Item.handcuffs);
			case Move.useBeer: return use(state, Item.beer);
			case Move.useCigarettePack: return use(state, Item.cigarettePack);
			case Move.useHandSaw: return use(state, Item.handSaw);
		}
	}

	immutable state0 = State(game);

	if (state0.totalShells == 0)
	{
		// End of round.
		driver.log(() => "Starting new round.");

		State state1 = state0;

		// Handcuffs come off. How will you grab the items otherwise?
		state1.handcuffs[] = HandcuffState.none;

		// Refill magazine.
		return driver.choice!ubyte(
			ChoiceMode.random,
			() => "How many shells are loaded?",
			(totalShells) {
				State state2 = state1;
				auto liveShells = cast(ubyte)(totalShells / 2); // rounding down
				auto blankShells = cast(ubyte)(totalShells - liveShells);
				driver.log(() => blankShells.to!string ~ " blank, " ~ liveShells.to!string ~ " live.");
				state2.shells[ShellType.blank] = blankShells;
				state2.shells[ShellType.live] = liveShells;

				// Grant items
				return driver.choice!ubyte(
					ChoiceMode.random,
					() => "How many items are granted?",
					(numItems) {
						Score grantItems(ref const State state3, ubyte[enumLength!Character] numRemaining)
						{
							foreach (character; Character.init .. enumLength!Character)
								if (numRemaining[character])
								{
									if (state3.totalItems(character) == maxItems)
									{
										driver.log(() => (character == Character.player ? "You don't" : "The dealer doesn't") ~ " have any more room.");
										numRemaining[character] = 0;
										continue;
									}

									numRemaining[character]--;
									Item[enumLength!Item] itemChoices;
									size_t numItemChoices;
									foreach (item; Item.init .. enumLength!Item)
									{
										bool canAdd = {
											switch (item)
											{
												case Item.cigarettePack:
													return state3.items[character][Item.cigarettePack] < 2;
												default:
													return true;
											}
										}();
										if (canAdd)
											itemChoices[numItemChoices++] = item;
									}
									return driver.choice!Item(
										ChoiceMode.random,
										() => "What item did " ~ (character == Character.player ? "you" : "the dealer") ~ " get?",
										(item) {
											State state4 = state3;
											state4.items[character][item]++;
											return grantItems(state4, numRemaining);
										},
										(item) => capitalize(itemDescriptions[item]),
										itemChoices[0 .. numItemChoices],
									);
								}

							// It's always the player's turn first.
							State state4 = state3;
							state4.currentTurn = Character.player;

							driver.log(() => "Round begins.");
							return driver.recurse(state4);
						}
						return grantItems(state2, [numItems, numItems]);
					},
					numItems => numItems.to!string,
					0, 1, 2, 3, 4
				);
			},
			totalShells => totalShells.to!string,
			2, 3, 4, 5, 6, 7, 8
		);
	}

	if (state0.handcuffs[state0.currentTurn] == HandcuffState.willSkip)
	{
		State state1 = state0;
		driver.log(() => state1.currentTurn == Character.player
			? "You are handcuffed and skip your turn."
			: "The dealer is handcuffed and skips their turn."
		);
		state1.handcuffs[state1.currentTurn] = HandcuffState.willBreak;
		switchTurn(state1);
		return driver.recurse(state1);
	}

	final switch (state0.currentTurn)
	{
		case Character.player:
			// Assume that the player will proceed according to what's best for them.
			return driver.choice!Move(
				ChoiceMode.best,
				() => "What will you do?",
				move => tryMove(state0, move),
				move => getMoveDescription(move, Character.player),
				EnumMembers!Move,
			);

		case Character.dealer:
			final switch (opponent)
			{
				case Opponent.perfect:
					return driver.choice!Move(
						ChoiceMode.worst,
						() => "What does the dealer do?",
						move => tryMove(state0, move),
						move => getMoveDescription(move, Character.dealer),
						EnumMembers!Move,
					);
				case Opponent.game:
					Score dealerAI(ref const State state1, bool dealerCanHeal)
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
								() => "The dealer flips a coin...",
								getScore,
								item => (item == items[0] ? "Heads" : "Tails") ~ ": " ~ getDescription(item),
								items
							);
						}


						// Simulate game AI
						Nullable!Character dealerTarget;
						Nullable!ShellType knownShell;
						bool dealerKnowsShell;

						if (!state1.nextShell.isNull)
						{
							// If it's resolved, it's guaranteed that the current character knows it
							knownShell = state1.nextShell;
							dealerTarget = knownShell.get() == ShellType.live
								? Character.player
								: Character.dealer;
							dealerKnowsShell = true;
						}

						if (state1.totalShells == 1)
						{
							knownShell = state1.shells[ShellType.live]
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
						if (state1.items[state1.currentTurn][Item.lookingGlass] && !dealerKnowsShell && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useLookingGlass;
						if (state1.items[state1.currentTurn][Item.cigarettePack] && state1.health[state1.currentTurn] < dealerCanHeal)
							itemOptions[numItemOptions++] = Move.useCigarettePack;
						if (state1.items[state1.currentTurn][Item.beer] && knownShell != ShellType.live.nullable && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useBeer;
						if (state1.items[state1.currentTurn][Item.handcuffs] && state1.handcuffs[state1.currentTurn.other] == HandcuffState.none && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useHandcuffs;
						if (state1.items[state1.currentTurn][Item.handSaw] && !state1.shotgunSawedOff && knownShell == ShellType.live.nullable)
							itemOptions[numItemOptions++] = Move.useHandSaw;
						if (numItemOptions)
							return driver.choice!Move(
								ChoiceMode.unknown,
								() => "The dealer will use an item...",
								move => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								itemOptions[0 .. numItemOptions]
							);

						if (state1.items[state1.currentTurn][Item.handSaw] && !state1.shotgunSawedOff && knownShell != nullable(ShellType.blank))
							return coinFlip!Move(
								move => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								Move.shootSelf, Move.useHandSaw,
							);

						if (dealerTarget.isNull)
							return coinFlip!Move(
								move => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								Move.shootSelf, Move.shootOther,
							);
						else
						{
							auto move = dealerTarget.get() == Character.dealer ? Move.shootSelf : Move.shootOther;
							return tryMove(state1, move);
						}
					}

					// Resolve if dealer can heal here
					if (state0.items[state0.currentTurn][Item.cigarettePack])
						return resolveCanHealTo(state0, cast(ubyte)(state0.health[state0.currentTurn] + 1), (State state1, bool result) { return dealerAI(state1, result); });
					else
						return dealerAI(state0, false);
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
		/// Caller should be careful to not mutate external state in `getScore`!
		Score choice(T)(
			ChoiceMode mode,
			scope string delegate() description,
			scope Score delegate(T) getScore,
			scope string delegate(T) getDescription,
			scope T[] items...
		) { assert(false); }
	}

	Game game;
	TestDriver driver;
	if (false)
		expand(game, driver, Opponent.game);
}

/// Standard `Driver.choice` implementation.
Score graphChoice(T)(
	ChoiceMode mode,
	scope string delegate() description,
	scope Score delegate(T) getScore,
	scope string delegate(T) getDescription,
	scope T[] items...
) {
	final switch (mode)
	{
		case ChoiceMode.random:
			Score sum = 0;
			size_t total = 0;
			foreach (item; items)
			{
				auto itemScore = getScore(item);
				if (!itemScore.isNaN)
				{
					sum += itemScore;
					total ++;
				}
			}
			return sum / total;

		case ChoiceMode.randomWithDuplicates:
			static if (is(T == bool))
				enum size_t card = 2;
			else
			static if (is(T == enum))
				enum size_t card = enumLength!T;
			else
				enum size_t card = 0;
			static if (card)
			{
				size_t[card] counts;
				foreach (item; items)
					counts[item]++;

				Score sum = 0;
				size_t total = 0;
				foreach (index; 0 .. card)
				{
					auto item = cast(T)index;
					auto count = counts[index];
					if (!count)
						continue;

					auto itemScore = getScore(item);
					if (!itemScore.isNaN)
					{
						sum += itemScore * count;
						total += count;
					}
				}
				return sum / total;

			}
			else
				assert(false);

		case ChoiceMode.best:
			Score bestScore = -Score.max;
			foreach (item; items)
			{
				auto itemScore = getScore(item);
				if (itemScore > bestScore) // Comparison with NaN will yield false
					bestScore = itemScore;
			}
			assert(bestScore != -Score.max, "All choices are invalid");
			return bestScore;

		case ChoiceMode.worst:
		case ChoiceMode.unknown:
			Score worstScore = Score.max;
			foreach (item; items)
			{
				auto itemScore = getScore(item);
				if (itemScore < worstScore) // Comparison with NaN will yield false
					worstScore = itemScore;
			}
			assert(worstScore != Score.max, "All choices are invalid");
			return worstScore;
	}
}

unittest
{
	struct Driver
	{
		void log(scope string delegate() message) nothrow @nogc {}
		Score recurse(const ref Game game) nothrow @nogc { return 0; }
		alias choice = graphChoice;
	}

	Game game;
	Driver driver;
	expand(game, driver, Opponent.game);
}
