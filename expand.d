import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.sorting;
import std.array : join;
import std.conv : to;
import std.math.traits;
import std.stdio;
import std.string : capitalize;
import std.traits;
import std.typecons;

import ae.utils.math.combinatorics;
import ae.utils.meta;

import game;

enum Move : ubyte
{
	shootSelf,
	shootOther,
	useMagnifyingGlass,
	useHandcuffs,
	useBeer,
	useCigarettePack,
	useHandSaw,
}

string[enumLength!Item] itemDescriptions = [
	"a Magnifying Glass",
	"Handcuffs",
	"a Beer",
	"a Cigarette Pack",
	"a Hand Saw",
];

string getMoveDescription(Move move, Character who)
{
	final switch (move)
	{
		case Move.shootSelf       : return who == Character.player ? "Shoot yourself"   : "Shoot themselves";
		case Move.shootOther      : return who == Character.player ? "Shoot the dealer" : "Shoot you";
		case Move.useMagnifyingGlass : return "Use a Magnifying Glass";
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
	/// Something that's usually always decided in some way,
	/// but overridable in interactive mode.
	first,
}

enum Opponent
{
	game,
	perfect,
}

Score expand(Driver)(const ref Game game, Driver driver, Opponent opponent)
{
	// Ugly hack to work around attribute inference with recursion not working, TODO
	template Dg(string def, Args...)
	{
		enum noGC = is(typeof({ static assert(driver.interactive == false); }));
		static if (noGC)
			mixin(`alias Dg = ` ~ def ~ ` nothrow @nogc;`);
		else
			mixin(`alias Dg = ` ~ def ~ `;`);
	}

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

	Score resolveCanHealTo(const ref State state0, ubyte targetHealth, scope Dg!q{Score delegate(State newState, bool result)} handler)
	{
		State state1 = state0;
		state1.initialHealthMin = state1.initialHealthMin.max(state1.health[].fold!max(ubyte(0)));

		if (targetHealth > state1.initialHealthMax)
			return handler(state1, false);
		else
		if (targetHealth <= state1.initialHealthMin)
			return handler(state1, true);
		else
			return driver.choice!(ChoiceMode.unknown, bool)(
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

		if (state.handcuffs[state.currentTurn] == HandcuffState.willSkip)
		{
			driver.log(() => state.currentTurn == Character.player
				? "You are handcuffed and skip your turn."
				: "The dealer is handcuffed and skips their turn."
			);
			if (state.totalShells == 0)
				driver.log(() => "(It doesn't matter, the round is ending.)");
			state.handcuffs[state.currentTurn] = HandcuffState.willBreak;
			return switchTurn(state);
		}

		if (state.handcuffs[state.currentTurn] == HandcuffState.willBreak)
		{
			driver.log(() => (state.currentTurn == Character.player ? "Your" : "The dealer's") ~ " handcuffs break off.");
			state.handcuffs[state.currentTurn] = HandcuffState.none;
		}
	}

	Score resolveRound(const ref State state, scope Dg!q{Score delegate(ShellType shellType, ref State newState)} handler)
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

		return driver.choice!(ChoiceMode.randomWithDuplicates, ShellType)(
			() => "What shell was in the chamber?",
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
								return driver.gameOver(false);
							case Character.dealer:
								driver.log(() => "The dealer is out. You win!");
								return driver.gameOver(true);
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

	Score use(ref const State state0, Item item)
	{
		if (!state0.items[state0.currentTurn][item])
			return Score.nan;
		driver.log(() => (state0.currentTurn == Character.player ? "You use " : "The dealer uses ") ~ itemDescriptions[item] ~ ".");
		State state1 = state0;
		state1.items[state1.currentTurn][item]--;
		final switch (item)
		{
			case Item.handcuffs:
				if (state1.handcuffs[state1.currentTurn.other])
					return Score.nan;
				state1.handcuffs[state1.currentTurn.other] = HandcuffState.willSkip;
				driver.log(() => (state1.currentTurn.other == Character.player ? "You are" : "The dealer is") ~ " now handcuffed.");
				return driver.recurse(state1);
			case Item.magnifyingGlass:
				if (!state1.nextShell.isNull)
					return Score.nan;
				return resolveRound(state1, (ShellType shellType, ref State state2) {
					driver.log(() => (state2.currentTurn == Character.player ? "You now know" : "The dealer now knows") ~ " that the next shell is " ~ shellType.to!string ~ ".");
					state2.nextShell = shellType;
					return driver.recurse(state2);
				});
			case Item.beer:
				return resolveRound(state1, (ShellType shellType, ref State state2) {
					driver.log(() => (state2.currentTurn == Character.player ? "You rack" : "The dealer racks") ~ " the shotgun, and a " ~ shellType.to!string ~ " shell is ejected.");
					return driver.recurse(state2);
				});
			case Item.cigarettePack:
				Score smoke(State state2, bool canHeal)
				{
					if (canHeal)
					{
						driver.log(() => (state2.currentTurn == Character.player ? "You restore" : "The dealer restores") ~ " one charge.");
						state2.health[state2.currentTurn]++;
					}
					else
						driver.log(() => (state2.currentTurn == Character.player ? "You are" : "The dealer is") ~ " already at maximum charges.");
					return driver.recurse(state2);
				}
				return resolveCanHealTo(state1, cast(ubyte)(state1.health[state1.currentTurn] + 1), &smoke);
			case Item.handSaw:
				if (state1.shotgunSawedOff)
					return Score.nan;
				state1.shotgunSawedOff = true;
				driver.log(() => "The shotgun barrel is now sawed off.");
				return driver.recurse(state1);
		}
	}

	Score tryMove(ref const State state, Move move)
	{
		final switch (move)
		{
			case Move.shootSelf : return shoot(state, state.currentTurn);
			case Move.shootOther: return shoot(state, state.currentTurn.other);
			case Move.useMagnifyingGlass: return use(state, Item.magnifyingGlass);
			case Move.useHandcuffs: return use(state, Item.handcuffs);
			case Move.useBeer: return use(state, Item.beer);
			case Move.useCigarettePack: return use(state, Item.cigarettePack);
			case Move.useHandSaw: return use(state, Item.handSaw);
		}
	}

	immutable state0 = State(game);

	if (state0.totalShells == 0)
	{
		// Handcuffs come off. How will you grab the items otherwise?
		foreach (Character character, handcuffState; state0.handcuffs)
			if (handcuffState)
			{
				State state1 = state0;
				state1.handcuffs[character] = HandcuffState.none;
				driver.log(() => "The round is ending; " ~ (character == Character.player ? "your" : "the dealer's") ~ " handcuffs come off.");
				return driver.recurse(state1);
			}

		// It's always the player's turn first.
		if (state0.currentTurn != Character.player)
		{
			State state1 = state0;
			state1.currentTurn = Character.player;
			driver.log(() => "The round is ending; the dealer's turn ends.");
			return driver.recurse(state1);
		}

		// End of round.
		driver.log(() => "Starting new round.");

		State state1 = state0;

		// Use a different flow depending on if the driver is interactive.
		// If yes, use a series of questions suitable for interactive use (humans).
		// If no, use a more efficient flow with fewer questions.
		// The result should be the same.
		if (driver.interactive)
		{
			// Ask questions in the order that the game presents information to players.
			enum Phase
			{
				playerItems,
				charges,
				shells,
				dealerItems,
				end,
			}
			enum maxGrantedItems = 4;
			static struct AskState
			{
				State state;
				alias state this;

				Phase phase;

				// The player gets between 0 and 4 items.  The dealer gets the same amount.
				// We want to ask questions in the order that the game asks them...
				// but it gets complicated because:
				// 1. The item number distribution should be linear,
				//    but the number of granted items can't be known until the end
				// 2. Characters can run out of inventory space
				//    (so the total number of items may not even be knowable...)
				// These track the lower and upper bound (inclusive):
				size_t numItemsLow = 0, numItemsHigh = maxGrantedItems;
				size_t[enumLength!Character] itemIndex;
			}

			scope Dg!(q{Score delegate(ref const Args[0])}, AskState) ask;
			ask = (ref const AskState state2)
			{
				Score nextPhase(ref const AskState state3)
				{
					AskState state4 = state3;
					state4.phase++;
					return ask(state4);
				}

				final switch (state2.phase)
				{
					case Phase.playerItems:
					case Phase.dealerItems:
						auto character = state2.phase == Phase.playerItems ? Character.player : Character.dealer;
						auto itemsSoFar = state2.itemIndex[character];

						if (itemsSoFar == state2.numItemsHigh)
							return nextPhase(state2);

						// Some slightly hairy math, in order to fairly represent the linear
						// distribution of number of granted items without asking additional questions:
						size_t noItemChanceNumerator, noItemChanceDenominator;
						if (itemsSoFar < state2.numItemsLow)
						{
							// We *know* an item will be granted.
							noItemChanceNumerator = 0;
							noItemChanceDenominator = 1;
						}
						else
						{
							noItemChanceNumerator = 1;
							noItemChanceDenominator = maxGrantedItems + 1 - itemsSoFar;
						}

						if (state2.totalItems(character) == maxItems)
						{
							if (character == Character.player)
							{
								// Same as below, except "false" instead of null and "true" except non-null.
								bool[maxGrantedItems + 1] itemChoices; size_t numItemChoices;

								foreach (i; 0 .. noItemChanceDenominator)
									itemChoices[numItemChoices++] = !(i < noItemChanceNumerator);

								return driver.choice!(ChoiceMode.randomWithDuplicates, bool)(
									() => "No more room, but did " ~ (character == Character.player ? "you" : "the dealer") ~ " get " ~ ["an", "a second", "a third", "a fourth"][itemsSoFar] ~ " item?",
									(gotItem) {
										AskState state3 = state2;
										if (!gotItem)
										{
											if (state3.numItemsHigh > itemsSoFar)
												state3.numItemsHigh = itemsSoFar;
										}
										else
										{
											if (state3.numItemsLow < itemsSoFar + 1)
												state3.numItemsLow = itemsSoFar + 1;
										}
										return nextPhase(state3);
									},
									(gotItem) => gotItem ? "Yes" : "No",
									itemChoices[0 .. numItemChoices],
								);
							}
							else
							{
								// I guess we'll never know.
								return nextPhase(state2);
							}
						}

						enum maxItemChoices = (enumLength!Item + 1) * (maxGrantedItems + 1);
						Nullable!Item[maxItemChoices] itemChoices; size_t numItemChoices;

						foreach (item; Item.init .. enumLength!Item)
						{
							bool canAdd = {
								switch (item)
								{
									case Item.cigarettePack:
										return state2.items[character][Item.cigarettePack] < 2;
									default:
										return true;
								}
							}();
							if (!canAdd)
								continue;

							foreach (i; 0 .. noItemChanceDenominator)
							{
								if (i < noItemChanceNumerator)
									itemChoices[numItemChoices++] = Nullable!Item.init;
								else
									itemChoices[numItemChoices++] = item;
							}
						}

						return driver.choice!(ChoiceMode.randomWithDuplicates, Nullable!Item)(
							() => "What is the" ~ (state2.numItemsHigh == 1 ? "" : [" first", " second", " third", " fourth"][itemsSoFar]) ~ " item that " ~ (character == Character.player ? "you get" : "the dealer gets") ~ "?",
							(item) {
								AskState state3 = state2;
								if (item.isNull)
								{
									if (state3.numItemsHigh > itemsSoFar)
										state3.numItemsHigh = itemsSoFar;
									return nextPhase(state3);
								}
								else
								{
									if (state3.numItemsLow < itemsSoFar + 1)
										state3.numItemsLow = itemsSoFar + 1;
									state3.items[character][item.get()]++;
									state3.itemIndex[character]++;
									return ask(state3);
								}
							},
							(item) => item.isNull
								? "Nothing (no " ~ (itemsSoFar == 0 ? "" : "more ") ~ "items)"
								: capitalize(itemDescriptions[item.get()]),
							itemChoices[0 .. numItemChoices],
						);

					// Note, this could also be done by making 0 HP representable...
					case Phase.charges:
						return driver.choice!(ChoiceMode.first, ubyte)(
							() => "Reset charges?",
							(charges) {
								AskState state3 = state2;
								if (charges)
								{
									state3.health[] = charges;
									driver.log(() => "Both characters now have " ~ charges.to!string ~ " charges.");
								}
								return nextPhase(state3);
							},
							charges => charges ? "Yes, " ~ charges.to!string ~ " charges" : "No",
							0, 2, 3, 4
						);

					case Phase.shells:
						return driver.choice!(ChoiceMode.random, ubyte)(
							() => "How many shells are loaded?",
							(totalShells) {
								AskState state3 = state2;
								auto liveShells = cast(ubyte)(totalShells / 2); // rounding down
								auto blankShells = cast(ubyte)(totalShells - liveShells);
								driver.log(() => blankShells.to!string ~ " blank, " ~ liveShells.to!string ~ " live.");
								state3.shells[ShellType.blank] = blankShells;
								state3.shells[ShellType.live] = liveShells;
								return nextPhase(state3);
							},
							totalShells => totalShells.to!string,
							2, 3, 4, 5, 6, 7, 8
						);

					case Phase.end:
						driver.log(() => "Round begins.");
						return driver.recurse(state2);
				}
			};
			auto askState = AskState(state1);
			return ask(askState);
		}
		else
			// Refill magazine.
			return driver.choice!(ChoiceMode.random, ubyte)(
				() => "How many shells are loaded?",
				(totalShells) {
					State state2 = state1;
					auto liveShells = cast(ubyte)(totalShells / 2); // rounding down
					auto blankShells = cast(ubyte)(totalShells - liveShells);
					driver.log(() => blankShells.to!string ~ " blank, " ~ liveShells.to!string ~ " live.");
					state2.shells[ShellType.blank] = blankShells;
					state2.shells[ShellType.live] = liveShells;

					// Grant items
					return driver.choice!(ChoiceMode.random, ubyte)(
						() => "How many items are granted?",
						(numItems) {
							scope Dg!q{Score delegate(ref const State, Character)} grantItems;
							grantItems = (ref const State state3, Character character)
							{
								if (character == enumLength!Character)
								{
									// Done granting items.

									driver.log(() => "Round begins.");
									return driver.recurse(state3);
								}

								auto remainingRoom = maxItems - state3.totalItems(character);
								if (remainingRoom < numItems)
									driver.log(() => (character == Character.player ? "You don't" : "The dealer doesn't") ~ " have room to receive " ~ numItems.to!string ~ " item" ~ (numItems == 1 ? "" : "s") ~ ".");

								auto grantedItems = min(numItems, remainingRoom);
								if (grantedItems == 0)
								{
									driver.log(() => (character == Character.player ? "You don't" : "The dealer doesn't") ~ " receive any items.");
									character++;
									return grantItems(state3, character);
								}

								driver.log(() => (character == Character.player ? "You receive" : "The dealer receives") ~ " " ~ grantedItems.to!string ~ " item" ~ (grantedItems == 1 ? "" : "s") ~ ".");

								static foreach (grantedItemsCT; 1 .. 4 + 1)
									if (grantedItemsCT == grantedItems)
										static foreach (numCigarettePacksCT; 0 .. 2 + 1)
											if (numCigarettePacksCT == state3.items[character][Item.cigarettePack])
											{
												alias PackedItems = ubyte;
												alias ItemCNS = CNS!(/*PackedItems*/uint, /*Item*/ubyte, grantedItemsCT, enumLength!Item, true, true);
												static assert(ItemCNS.packedCard <= PackedItems.max);

												PackedItems[] genItemChoiceTable()
												{
													PackedItems[] result;

													/*Item*/ubyte[grantedItemsCT] items;
													void iterate(size_t itemIndex, int remainingCigarettePacks)
													{
														if (itemIndex == grantedItemsCT)
														{
															// `dup` for https://issues.dlang.org/show_bug.cgi?id=24354
															/*Item*/ubyte[grantedItemsCT] sortedItems = items.dup;
															sortedItems[].sort();
															result ~= cast(PackedItems)ItemCNS.pack(sortedItems);
														}
														else
															foreach (item; Item.init .. enumLength!Item)
															{
																if (item == Item.cigarettePack && !remainingCigarettePacks)
																	continue;
																items[itemIndex] = item;
																iterate(itemIndex + 1, remainingCigarettePacks - (item == Item.cigarettePack ? 1 : 0));
															}
													}
													iterate(0, 2 - numCigarettePacksCT);
													return result;
												}

												static immutable choiceTable = genItemChoiceTable();

												return driver.choice!(ChoiceMode.randomWithDuplicates, PackedItems)(
													() => "What items did " ~ (character == Character.player ? "you" : "the dealer") ~ " get?",
													(packedItems) {
														auto items = ItemCNS.unpack(packedItems);
														State state4 = state3;
														foreach (item; items)
															state4.items[character][item]++;
														assert(state4.totalItems(character) <= maxItems);
														auto nextCharacter = character; nextCharacter++;
														return grantItems(state4, nextCharacter);
													},
													(packedItems) {
														auto items = ItemCNS.unpack(packedItems);
														return items[].map!(item => itemDescriptions[item]).join(", ").capitalize;
													},
													choiceTable,
												);
											}

								driver.log(() => "Impossible combination of granted items / cigarette packs.");
								return Score.nan;
							};
							return grantItems(state2, Character.init);
						},
						numItems => numItems.to!string,
						0, 1, 2, 3, 4
					);
				},
				totalShells => totalShells.to!string,
				2, 3, 4, 5, 6, 7, 8
			);
	}

	assert(!state0.handcuffs[state0.currentTurn]);

	final switch (state0.currentTurn)
	{
		case Character.player:
			// Assume that the player will proceed according to what's best for them.
			return driver.choice!(ChoiceMode.best, Move)(
				() => "What will you do?",
				move => tryMove(state0, move),
				move => getMoveDescription(move, Character.player),
				EnumMembers!Move,
			);

		case Character.dealer:
			final switch (opponent)
			{
				case Opponent.perfect:
					return driver.choice!(ChoiceMode.worst, Move)(
						() => "What does the dealer do?",
						move => tryMove(state0, move),
						move => getMoveDescription(move, Character.dealer),
						EnumMembers!Move,
					);
				case Opponent.game:
					Score dealerAI(ref const State state1, bool dealerCanHeal)
					{
						Score coinFlip(T)(
							scope Dg!(q{Score delegate(Args[0])}, T) getScore,
							scope string delegate(T) getDescription,
							scope T[] items...
						)
						{
							assert(items.length == 2);
							return driver.choice!(ChoiceMode.random, T)(
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
						if (state1.items[state1.currentTurn][Item.magnifyingGlass] && !dealerKnowsShell && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useMagnifyingGlass;
						if (state1.items[state1.currentTurn][Item.cigarettePack] && dealerCanHeal)
							itemOptions[numItemOptions++] = Move.useCigarettePack;
						if (state1.items[state1.currentTurn][Item.beer] && knownShell != ShellType.live.nullable && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useBeer;
						if (state1.items[state1.currentTurn][Item.handcuffs] && state1.handcuffs[state1.currentTurn.other] == HandcuffState.none && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useHandcuffs;
						if (state1.items[state1.currentTurn][Item.handSaw] && !state1.shotgunSawedOff && knownShell == ShellType.live.nullable)
							itemOptions[numItemOptions++] = Move.useHandSaw;
						if (numItemOptions)
							return driver.choice!(ChoiceMode.unknown, Move)(
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

						if (state1.shotgunSawedOff)
							dealerTarget = Character.player;

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
		enum interactive = false;

		/// Make a note.
		void log(scope string delegate() message) nothrow @nogc {}

		/// Recursive search.
		/// Get the score of another game state,
		/// as if we descended recursively into it.
		Score recurse(const ref Game game) nothrow @nogc { assert(false); }

		/// A choice is happening.
		/// Filter out NaNs!
		/// Caller should be careful to not mutate external state in `getScore`!
		Score choice(ChoiceMode mode, T)(
			scope string delegate() description,
			scope Score delegate(T) nothrow @nogc getScore,
			scope string delegate(T) getDescription,
			scope const(T)[] items...
		) nothrow @nogc { assert(false); }

		/// End condition.
		Score gameOver(bool playerWon) nothrow @nogc { return playerWon ? scoreWin : scoreLose; }
	}

	Game game;
	TestDriver driver;
	if (false)
		expand(game, driver, Opponent.game);
}

template itemCardinality(T)
{
	static if (is(T == Nullable!U, U))
		enum size_t itemCardinality = 1 + itemCardinality!U;
	else
	static if (is(T == bool))
		enum size_t itemCardinality = 2;
	else
	static if (is(T == enum))
		enum size_t itemCardinality = enumLength!T;
	else
	static if (is(T == ubyte))
		enum size_t itemCardinality = 256;
	else
		enum size_t itemCardinality = 0;
}

size_t toCardinal(T)(T value)
if (itemCardinality!T != 0)
{
	static if (is(T == Nullable!U, U))
		return value.isNull ? 0 : 1 + value.get().toCardinal();
	else
		return value;
}

T fromCardinal(T)(size_t cardinal)
if (itemCardinality!T != 0)
{
	assert(cardinal < itemCardinality!T);
	static if (is(T == Nullable!U, U))
		return cardinal == 0 ? T.init : (cardinal - 1).fromCardinal!U().nullable;
	else
		return cast(T)cardinal;
}

/// Standard `Driver.choice` implementation.
template graphChoice(alias GetScore)
{
	Score graphChoice(ChoiceMode mode, T)(
		scope string delegate() description,
		scope GetScore!T getScore,
		scope string delegate(T) getDescription,
		scope const(T)[] items...
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
				enum card = itemCardinality!T;
				static if (card)
				{
					size_t[card] counts;
					foreach (T item; items)
						counts[item.toCardinal()]++;

					Score sum = 0;
					size_t total = 0;
					foreach (index; 0 .. card)
					{
						auto item = index.fromCardinal!T;
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

			case ChoiceMode.first:
				return getScore(items[0]);
		}
	}
}

Score graphGameOver(bool playerWon) nothrow @nogc { return playerWon ? scoreWin : scoreLose; }

unittest
{
	struct Driver
	{
		enum interactive = false;
		void log(scope string delegate() message) nothrow @nogc {}
		Score recurse(const ref Game game) nothrow @nogc { return 0; }
		alias GetScore(T) = Score delegate(T) nothrow @nogc;
		alias choice = graphChoice!GetScore;
		alias gameOver = graphGameOver;
	}

	Game game;
	Driver driver;
	expand(game, driver, Opponent.game);
}
