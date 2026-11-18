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
	useInverter,
	useBurnerPhone,
	useAdrenaline,
	useExpiredMedicine,
}

string[enumLength!Item] itemDescriptions = [
	"a Magnifying Glass",
	"Handcuffs",
	"a Beer",
	"a Cigarette Pack",
	"a Hand Saw",
	"an Inverter",
	"a Burner Phone",
	"Adrenaline",
	"Expired Medicine",
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
		case Move.useInverter      : return "Use an Inverter";
		case Move.useBurnerPhone   : return "Use a Burner Phone";
		case Move.useAdrenaline    : return "Use Adrenaline";
		case Move.useExpiredMedicine: return "Use Expired Medicine";
	}
}

alias Score = double;
enum Score scoreLose = 0;
enum Score scoreWin = 1;
enum Score scoreIndeterminate = (scoreLose + scoreWin) / 2;

enum ChoiceMode
{
	random,
	randomWeighted,
	best,
	worst,
	unknown,
	first,
}

struct Weighted(T, Weight = size_t)
{
	T value;
	Weight weight = 0;
}

enum Opponent
{
	game,
	perfect,
}

Score expand(Driver)(const ref Game game, Driver driver, Opponent opponent)
{
	template Dg(string def, Args...)
	{
		enum noGC = is(typeof({ static assert(driver.interactive == false); }));
		static if (noGC)
			mixin(`alias Dg = ` ~ def ~ ` nothrow @nogc;`);
		else
			mixin(`alias Dg = ` ~ def ~ `;`);
	}
	
	// Спочатку оголошуємо State!
	struct State
	{
		Game game;
		alias game this;
		ubyte initialHealthMin = 2, initialHealthMax = 4;
	}

	// Тепер аліаси
	alias DgMove = Dg!(q{Score delegate(Move)});
	alias DgItem = Dg!(q{Score delegate(Item)});
	alias DgHeal = Dg!(q{Score delegate(State, bool)});

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

	/// Bookkeeping after a shell is taken from the (unknown) magazine.
	static void afterPoolDraw(ref State state)
	{
		if (state.dealerPhoneExcluded)
			state.dealerPhoneExcluded = false; // that was not the revealed shell
		else
		if (state.dealerPhoneCandidates)
			state.dealerPhoneCandidates--; // (approximation: assume it was not the revealed one)
	}

	static ShellType applyInversion(ref State state, ShellType drawn)
	{
		if (!state.chamberInverted)
			return drawn;
		state.chamberInverted = false;
		return drawn == ShellType.blank ? ShellType.live : ShellType.blank;
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

		if (!state.futureShell.isNull && state.futureShellCountdown == 1)
		{
			State newState = state;
			auto shellType = newState.futureShell.get();
			newState.futureShell.nullify();
			newState.futureShellCountdown = 0;
			newState.shells[shellType]--;
			afterPoolDraw(newState);
			auto actualType = applyInversion(newState, shellType);
			return handler(actualType, newState);
		}

		Weighted!ShellType[enumLength!ShellType] options;
		foreach (shellType; ShellType.init .. enumLength!ShellType)
		{
			size_t weight = state.shells[shellType];
			if (!state.futureShell.isNull && state.futureShell.get() == shellType)
				weight--;
			options[shellType] = Weighted!ShellType(shellType, weight);
		}

		return driver.choice!(ChoiceMode.randomWeighted, Weighted!ShellType)(
			() => "What shell was in the chamber?",
			(shellType) {
				if (!shellType.weight)
					return Score.nan;
				State newState = state;
				newState.shells[shellType.value]--;
				if (!newState.futureShell.isNull)
					newState.futureShellCountdown--;
				afterPoolDraw(newState);
				auto actualType = applyInversion(newState, shellType.value);
				return handler(actualType, newState);
			},
			shellType => state.chamberInverted
				? ["Live (was blank before the Inverter)", "Blank (was live before the Inverter)"][shellType.value]
				: ["Blank", "Live"][shellType.value],
			options
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

			case Item.inverter:
				if (state1.nextShell.isNull
					&& !(!state1.futureShell.isNull && state1.futureShellCountdown == 1))
				{
					// The chambered shell is unknown: do not reveal it, just remember that it is flipped.
					state1.chamberInverted = !state1.chamberInverted;
					driver.log(() => (state1.currentTurn == Character.player ? "You use" : "The dealer uses")
						~ " the Inverter on the chambered shell. Its type is still unknown, but it is now flipped.");
					return driver.recurse(state1);
				}
				return resolveRound(state1, (ShellType shellType, ref State state2) {
					auto invertedType = shellType == ShellType.blank ? ShellType.live : ShellType.blank;
					driver.log(() => (state2.currentTurn == Character.player ? "You use" : "The dealer uses")
						~ " the Inverter on the chambered shell. It is now " ~ invertedType.to!string ~ ".");
					state2.nextShell = invertedType;
					return driver.recurse(state2);
				});

			case Item.burnerPhone:
			{
				if (state1.currentTurn == Character.dealer)
				{
					// The player does not hear what the phone told the dealer.
					if (state1.dealerPhoneCandidates)
						return Score.nan;
					auto candidates = state1.shells[].sum - (state1.nextShell.isNull ? 1 : 0);
					if (candidates < 1)
						return Score.nan;
					state1.dealerPhoneCandidates = cast(ubyte)candidates;
					state1.dealerPhoneExcluded = state1.nextShell.isNull;
					driver.log(() => "The dealer now knows one of the upcoming shells. You don't know which one or what it is.");
					return driver.recurse(state1);
				}
				if (!state1.futureShell.isNull)
					return Score.nan;
				if (state1.shells[].sum < 2)
					return Score.nan;

				Weighted!ShellType[enumLength!ShellType] typeOptions;
				foreach (shellType; ShellType.init .. enumLength!ShellType)
					typeOptions[shellType] = Weighted!ShellType(shellType, state1.shells[shellType]);

				return driver.choice!(ChoiceMode.randomWeighted, Weighted!ShellType)(
					() => "What is the type of the revealed future shell?",
					(revealedType) {
						if (!revealedType.weight)
							return Score.nan;

						auto maxCountdown = state1.shells[].sum;
						Weighted!ubyte[maxShells] countdownOptions; size_t numCountdownOptions;
						foreach (countdown; 2 .. maxCountdown + 1)
							countdownOptions[numCountdownOptions++] = Weighted!ubyte(cast(ubyte)countdown, 1);

						return driver.choice!(ChoiceMode.randomWeighted, Weighted!ubyte)(
							() => "How many shells from now is the revealed shell?",
							(countdown) {
								if (!countdown.weight)
									return Score.nan;
								State state2 = state1;
								state2.futureShell = revealedType.value;
								state2.futureShellCountdown = countdown.value;
								driver.log(() => (state2.currentTurn == Character.player ? "You learn" : "The dealer learns")
									~ " that the shell " ~ countdown.value.to!string ~ " shells from now is " ~ revealedType.value.to!string ~ ".");
								return driver.recurse(state2);
							},
							countdown => countdown.value.to!string,
							countdownOptions[0 .. numCountdownOptions],
						);
					},
					shellType => ["Blank", "Live"][shellType.value],
					typeOptions[]
				);
			}

			case Item.adrenaline:
			{
				Item[enumLength!Item] stealOptions; size_t numStealOptions;
				foreach (it; Item.init .. enumLength!Item)
				{
					if (it == Item.adrenaline || !state1.items[state1.currentTurn.other][it])
						continue;

					if (it == Item.handcuffs && state1.handcuffs[state1.currentTurn.other]) continue;
					if (it == Item.magnifyingGlass && !state1.nextShell.isNull) continue;
					if (it == Item.handSaw && state1.shotgunSawedOff) continue;
					if (it == Item.burnerPhone && (state1.currentTurn == Character.dealer
						? state1.dealerPhoneCandidates || state1.shells[].sum - (state1.nextShell.isNull ? 1 : 0) < 1
						: !state1.futureShell.isNull || state1.shells[].sum < 2)) continue;

					stealOptions[numStealOptions++] = it;
				}
				
				if (!numStealOptions)
					return Score.nan;

				scope DgItem afterSteal = cast(DgItem) (Item stolenItem) {
					State state2 = state1;
					state2.items[state2.currentTurn.other][stolenItem]--;
					state2.items[state2.currentTurn][stolenItem]++;
					driver.log(() => (state2.currentTurn == Character.player ? "You steal " : "The dealer steals ")
						~ itemDescriptions[stolenItem]
						~ (state2.currentTurn == Character.player ? " from the dealer and uses it immediately." : " from you and uses it immediately."));
					return use(state2, stolenItem);
				};

				if (state1.currentTurn == Character.player)
					return driver.choice!(ChoiceMode.best, Item)(
						() => "Which item will you steal?",
						afterSteal,
						stolenItem => itemDescriptions[stolenItem],
						stealOptions[0 .. numStealOptions],
					);
				else
					return driver.choice!(ChoiceMode.worst, Item)(
						() => "Which item will the dealer steal?",
						afterSteal,
						stolenItem => itemDescriptions[stolenItem],
						stealOptions[0 .. numStealOptions],
					);
			}

			case Item.expiredMedicine:
				return driver.choice!(ChoiceMode.randomWeighted, Weighted!bool)(
					() => "Does the Expired Medicine work?",
					(outcome) {
						if (!outcome.weight)
							return Score.nan;
						if (outcome.value)
						{
							Score healStep2(State state3, bool canHeal2)
							{
								if (canHeal2)
								{
									driver.log(() => (state3.currentTurn == Character.player ? "You regain" : "The dealer regains") ~ " another charge.");
									state3.health[state3.currentTurn]++;
								}
								return driver.recurse(state3);
							}
							Score healStep1(State state2, bool canHeal1)
							{
								if (canHeal1)
								{
									driver.log(() => (state2.currentTurn == Character.player ? "You regain" : "The dealer regains") ~ " a charge.");
									state2.health[state2.currentTurn]++;
								}
								return resolveCanHealTo(state2, cast(ubyte)(state2.health[state2.currentTurn] + 1), &healStep2);
							}
							driver.log(() => (state1.currentTurn == Character.player ? "The Expired Medicine works! You feel" : "The Expired Medicine works! The dealer feels") ~ " better.");
							return resolveCanHealTo(state1, cast(ubyte)(state1.health[state1.currentTurn] + 1), &healStep1);
						}
						else
						{
							State state2 = state1;
							driver.log(() => (state2.currentTurn == Character.player ? "The Expired Medicine backfires! You lose" : "The Expired Medicine backfires! The dealer loses") ~ " a charge.");
							state2.health[state2.currentTurn]--;
							if (state2.health[state2.currentTurn] <= 0)
								final switch (state2.currentTurn)
								{
									case Character.player:
										driver.log(() => "You are out. You lose!");
										return driver.gameOver(false);
									case Character.dealer:
										driver.log(() => "The dealer is out. You win!");
										return driver.gameOver(true);
								}
							return driver.recurse(state2);
						}
					},
					outcome => outcome.value ? "Works (+2 charges)" : "Backfires (-1 charge)",
					Weighted!bool(true, 2), Weighted!bool(false, 3) 
				);
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
			case Move.useInverter: return use(state, Item.inverter);
			case Move.useBurnerPhone: return use(state, Item.burnerPhone);
			case Move.useAdrenaline: return use(state, Item.adrenaline);
			case Move.useExpiredMedicine: return use(state, Item.expiredMedicine);
		}
	}

	immutable state0 = State(game);

	if (state0.totalShells == 0)
	{
		foreach (Character character, handcuffState; state0.handcuffs)
			if (handcuffState)
			{
				State state1 = state0;
				state1.handcuffs[character] = HandcuffState.none;
				driver.log(() => "The round is ending; " ~ (character == Character.player ? "your" : "the dealer's") ~ " handcuffs come off.");
				return driver.recurse(state1);
			}

		if (state0.currentTurn != Character.player)
		{
			State state1 = state0;
			state1.currentTurn = Character.player;
			driver.log(() => "The round is ending; the dealer's turn ends.");
			return driver.recurse(state1);
		}

		driver.log(() => "Starting new round.");

		State state1 = state0;

		if (driver.interactive)
		{
			enum Phase
			{
				itemsConfig,
				playerItems,
				charges,
				shells,
				dealerItems,
				end,
			}
			enum minGrantedItems = 1;
			enum maxGrantedItems = 4;
			static struct AskState
			{
				State state;
				alias state this;
				Phase phase;
				size_t numItemsLow, numItemsHigh;
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
					case Phase.itemsConfig:
						return driver.choice!(ChoiceMode.first, bool)(
							() => "Are items enabled?",
							(itemsEnabled) {
								AskState state3 = state2;
								if (itemsEnabled)
								{
									state3.numItemsLow = minGrantedItems;
									state3.numItemsHigh = maxGrantedItems;
								}
								else
								{
									state3.numItemsLow = 0;
									state3.numItemsHigh = 0;
								}
								return nextPhase(state3);
							},
							(itemsEnabled) => itemsEnabled ? "Yes" : "No (first act of story mode)",
							true, false,
						);

					case Phase.playerItems:
					case Phase.dealerItems:
						auto character = state2.phase == Phase.playerItems ? Character.player : Character.dealer;
						auto itemsSoFar = state2.itemIndex[character];

						if (itemsSoFar == state2.numItemsHigh)
							return nextPhase(state2);

						size_t noItemChanceNumerator, noItemChanceDenominator;
						if (itemsSoFar < state2.numItemsLow)
						{
							noItemChanceNumerator = 0;
							noItemChanceDenominator = 1;
						}
						else
						{
							noItemChanceNumerator = 1;
							noItemChanceDenominator = maxGrantedItems + 1 - itemsSoFar;
						}
						auto itemNotGrantedWeight =                           noItemChanceNumerator;
						auto itemGrantedWeight    = noItemChanceDenominator - noItemChanceNumerator;

						if (state2.totalItems(character) == maxItems)
						{
							if (character == Character.player)
							{
								Weighted!bool[2] options = [
									{ false, itemNotGrantedWeight },
									{ true , itemGrantedWeight    },
								];

								return driver.choice!(ChoiceMode.randomWeighted, Weighted!bool)(
									() => "No more room, but did " ~ (character == Character.player ? "you" : "the dealer") ~ " get " ~ ["an", "a second", "a third", "a fourth"][itemsSoFar] ~ " item?",
									(gotItem) {
										if (!gotItem.weight)
											return Score.nan;
										AskState state3 = state2;
										if (!gotItem.value)
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
									(gotItem) => gotItem.value ? "Yes" : "No",
									options[],
								);
							}
							else
							{
								return nextPhase(state2);
							}
						}

						Weighted!(Nullable!Item)[enumLength!Item + 1] options;

						foreach (item; Item.init .. enumLength!Item)
							options[item].value = item.nullable;
						options[enumLength!Item].value = Nullable!Item.init;

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

							options[item           ].weight += itemGrantedWeight;
							options[enumLength!Item].weight += itemNotGrantedWeight;
						}

						return driver.choice!(ChoiceMode.randomWeighted, Weighted!(Nullable!Item))(
							() => "What is the" ~ (state2.numItemsHigh == 1 ? "" : [" first", " second", " third", " fourth"][itemsSoFar]) ~ " item that " ~ (character == Character.player ? "you get" : "the dealer gets") ~ "?",
							(item) {
								if (!item.weight)
									return Score.nan;
								AskState state3 = state2;
								if (item.value.isNull)
								{
									if (state3.numItemsHigh > itemsSoFar)
										state3.numItemsHigh = itemsSoFar;
									return nextPhase(state3);
								}
								else
								{
									if (state3.numItemsLow < itemsSoFar + 1)
										state3.numItemsLow = itemsSoFar + 1;
									state3.items[character][item.value.get()]++;
									state3.itemIndex[character]++;
									return ask(state3);
								}
							},
							(item) => item.value.isNull
								? "Nothing (no " ~ (itemsSoFar == 0 ? "" : "more ") ~ "items)"
								: capitalize(itemDescriptions[item.value.get()]),
							options[]
						);

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
								auto liveShells = cast(ubyte)(totalShells / 2);
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
			return driver.choice!(ChoiceMode.random, ubyte)(
				() => "How many shells are loaded?",
				(totalShells) {
					State state2 = state1;
					auto liveShells = cast(ubyte)(totalShells / 2); 
					auto blankShells = cast(ubyte)(totalShells - liveShells);
					driver.log(() => blankShells.to!string ~ " blank, " ~ liveShells.to!string ~ " live.");
					state2.shells[ShellType.blank] = blankShells;
					state2.shells[ShellType.live] = liveShells;

					return driver.choice!(ChoiceMode.random, ubyte)(
						() => "How many items are granted?",
						(numItems) {
							scope Dg!q{Score delegate(ref const State, Character)} grantItems;
							grantItems = (ref const State state3, Character character)
							{
								if (character == enumLength!Character)
								{
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
												alias PackedItems = ushort;
												alias ItemCNS = CNS!(uint, ubyte, grantedItemsCT, enumLength!Item, true, true);
												static assert(ItemCNS.packedCard <= PackedItems.max);

												Weighted!PackedItems[ItemCNS.packedCard] genItemChoiceTable()
												{
													Weighted!PackedItems[ItemCNS.packedCard] result;
													foreach (PackedItems packedItems, ref option; result)
														option.value = packedItems;

													ubyte[grantedItemsCT] items;
													void iterate(size_t itemIndex, int remainingCigarettePacks)
													{
														if (itemIndex == grantedItemsCT)
														{
															ubyte[grantedItemsCT] sortedItems = items.dup;
															sortedItems[].sort();
															auto packedItems = cast(PackedItems)ItemCNS.pack(sortedItems);
															result[packedItems].weight++;
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

												return driver.choice!(ChoiceMode.randomWeighted, Weighted!PackedItems)(
													() => "What items did " ~ (character == Character.player ? "you" : "the dealer") ~ " get?",
													(packedItems) {
														if (!packedItems.weight)
															return Score.nan;
														auto items = ItemCNS.unpack(packedItems.value);
														State state4 = state3;
														foreach (item; items)
															state4.items[character][item]++;
														assert(state4.totalItems(character) <= maxItems);
														auto nextCharacter = character; nextCharacter++;
														return grantItems(state4, nextCharacter);
													},
													(packedItems) {
														auto items = ItemCNS.unpack(packedItems.value);
														return items[].map!(item => itemDescriptions[item]).join(", ").capitalize;
													},
													choiceTable[]
												);
											}

								driver.log(() => "Impossible combination of granted items / cigarette packs.");
								return Score.nan;
							};
							return grantItems(state2, Character.init);
						},
						numItems => numItems.to!string,
						1, 2, 3, 4
					);
				},
				totalShells => totalShells.to!string,
				2, 3, 4, 5, 6, 7, 8
			);
	}

	assert(!state0.handcuffs[state0.currentTurn]);

	// The dealer's turn: is the chambered shell the one the dealer saw on their Burner Phone?
	if (state0.currentTurn == Character.dealer
		&& state0.dealerPhoneCandidates && !state0.dealerPhoneExcluded
		&& state0.nextShell.isNull)
	{
		size_t n = state0.dealerPhoneCandidates;
		return driver.choice!(ChoiceMode.randomWeighted, Weighted!bool)(
			() => "Is the chambered shell the one the dealer learned about with the Burner Phone?",
			(isIt) {
				if (!isIt.weight)
					return Score.nan;
				State state1 = state0;
				if (!isIt.value)
				{
					state1.dealerPhoneExcluded = true;
					state1.dealerPhoneCandidates--;
					if (!state1.dealerPhoneCandidates)
						state1.dealerPhoneExcluded = false;
					return driver.recurse(state1);
				}
				state1.dealerPhoneCandidates = 0;
				state1.dealerPhoneExcluded = false;
				return resolveRound(state1, (ShellType shellType, ref State state2) {
					driver.log(() => "The dealer knows that the chambered shell is " ~ shellType.to!string ~ ".");
					state2.nextShell = shellType;
					return driver.recurse(state2);
				});
			},
			isIt => isIt.value ? "Yes (the dealer knows this shell)" : "No",
			Weighted!bool(true, 1), Weighted!bool(false, n - 1),
		);
	}

	final switch (state0.currentTurn)
	{
		case Character.player:
			return driver.choice!(ChoiceMode.best, Move)(
				() => "What will you do?",
				cast(DgMove) (Move move) => tryMove(state0, move),
				move => getMoveDescription(move, Character.player),
				EnumMembers!Move,
			);

		case Character.dealer:
			final switch (opponent)
			{
				case Opponent.perfect:
					return driver.choice!(ChoiceMode.worst, Move)(
						() => "What does the dealer do?",
						cast(DgMove) (Move move) => tryMove(state0, move),
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

						Nullable!Character dealerTarget;
						Nullable!ShellType knownShell;
						bool dealerKnowsShell;

						if (!state1.nextShell.isNull)
						{
							knownShell = state1.nextShell;
							dealerTarget = knownShell.get() == ShellType.live
								? Character.player
								: Character.dealer;
							dealerKnowsShell = true;
						}

						if (state1.totalShells == 1)
						{
							knownShell = (state1.shells[ShellType.live] != 0) != state1.chamberInverted
								? ShellType.live
								: ShellType.blank;
							dealerTarget = knownShell.get() == ShellType.live
								? Character.player
								: Character.dealer;
							dealerKnowsShell = true;
						}

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
						if (state1.items[state1.currentTurn][Item.inverter] && knownShell == ShellType.blank.nullable && state1.totalShells != 1)
							itemOptions[numItemOptions++] = Move.useInverter;
						if (state1.items[state1.currentTurn][Item.burnerPhone] && !dealerKnowsShell && !state1.dealerPhoneCandidates && state1.shells[].sum >= 2)
							itemOptions[numItemOptions++] = Move.useBurnerPhone;
						if (state1.items[state1.currentTurn][Item.expiredMedicine] && dealerCanHeal
							&& (state1.health[state1.currentTurn] <= 1 || !state1.items[state1.currentTurn][Item.cigarettePack]))
							itemOptions[numItemOptions++] = Move.useExpiredMedicine;
						
						if (state1.items[state1.currentTurn][Item.adrenaline] && (
							   (state1.items[state1.currentTurn.other][Item.magnifyingGlass] && !dealerKnowsShell && state1.totalShells != 1)
							|| (state1.items[state1.currentTurn.other][Item.cigarettePack] && dealerCanHeal)
							|| (state1.items[state1.currentTurn.other][Item.beer] && knownShell != ShellType.live.nullable && state1.totalShells != 1)
							|| (state1.items[state1.currentTurn.other][Item.handcuffs] && state1.handcuffs[state1.currentTurn.other] == HandcuffState.none && state1.totalShells != 1)
							|| (state1.items[state1.currentTurn.other][Item.handSaw] && !state1.shotgunSawedOff && knownShell == ShellType.live.nullable)
							|| (state1.items[state1.currentTurn.other][Item.inverter] && knownShell == ShellType.blank.nullable && state1.totalShells != 1)
							|| (state1.items[state1.currentTurn.other][Item.burnerPhone] && !dealerKnowsShell && !state1.dealerPhoneCandidates && state1.shells[].sum >= 2)
							|| (state1.items[state1.currentTurn.other][Item.expiredMedicine] && dealerCanHeal && state1.health[state1.currentTurn] <= 1)
						))
							itemOptions[numItemOptions++] = Move.useAdrenaline;

						if (numItemOptions)
							return driver.choice!(ChoiceMode.unknown, Move)(
								() => "The dealer will use an item...",
								cast(DgMove) (Move move) => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								itemOptions[0 .. numItemOptions]
							);

						if (state1.items[state1.currentTurn][Item.handSaw] && !state1.shotgunSawedOff && knownShell != nullable(ShellType.blank))
							return coinFlip!Move(
								cast(DgMove) (Move move) => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								Move.shootSelf, Move.useHandSaw,
							);

						if (state1.shotgunSawedOff)
							dealerTarget = Character.player;

						if (dealerTarget.isNull)
							return coinFlip!Move(
								cast(DgMove) (Move move) => tryMove(state1, move),
								move => getMoveDescription(move, Character.dealer),
								Move.shootSelf, Move.shootOther,
							);
						else
						{
							auto move = dealerTarget.get() == Character.dealer ? Move.shootSelf : Move.shootOther;
							return tryMove(state1, move);
						}
					}

					if (state0.items[state0.currentTurn][Item.cigarettePack])
						return resolveCanHealTo(state0, cast(ubyte)(state0.health[state0.currentTurn] + 1), cast(DgHeal) (State state1, bool result) { return dealerAI(state1, result); });
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

		void log(scope string delegate() message) nothrow @nogc {}

		Score recurse(const ref Game game) nothrow @nogc { assert(false); }

		Score choice(ChoiceMode mode, T)(
			scope string delegate() description,
			scope Score delegate(T) nothrow @nogc getScore,
			scope string delegate(T) getDescription,
			scope const(T)[] items...
		) nothrow @nogc { assert(false); }

		Score gameOver(bool playerWon) nothrow @nogc { return playerWon ? scoreWin : scoreLose; }
	}

	Game game;
	TestDriver driver;
	if (false)
		expand(game, driver, Opponent.game);
}

template graphChoice(alias GetScore)
{
	Score graphChoice(ChoiceMode mode, T)(
		scope string delegate() description,
		scope GetScore!T getScore,
		scope string delegate(T) getDescription,
		scope const(T)[] items...
	) {
		static if (mode == ChoiceMode.random)
		{
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
		}
		else static if (mode == ChoiceMode.randomWeighted)
		{
			Score sum = 0;
			size_t total = 0;
			foreach (item; items)
			{
				if (!item.weight)
					continue;

				auto itemScore = getScore(item);
				if (!itemScore.isNaN)
				{
					sum += itemScore * item.weight;
					total += item.weight;
				}
			}
			return sum / total;
		}
		else static if (mode == ChoiceMode.best)
		{
			Score bestScore = -Score.max;
			foreach (item; items)
			{
				auto itemScore = getScore(item);
				if (itemScore > bestScore) 
					bestScore = itemScore;
			}
			assert(bestScore != -Score.max, "All choices are invalid");
			return bestScore;
		}
		else static if (mode == ChoiceMode.worst || mode == ChoiceMode.unknown)
		{
			Score worstScore = Score.max;
			foreach (item; items)
			{
				auto itemScore = getScore(item);
				if (itemScore < worstScore) 
					worstScore = itemScore;
			}
			assert(worstScore != Score.max, "All choices are invalid");
			return worstScore;
		}
		else static if (mode == ChoiceMode.first)
			return getScore(items[0]);
		else
			static assert(false);
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