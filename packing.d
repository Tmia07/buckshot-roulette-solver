import std.algorithm.searching;
import std.algorithm.sorting;
import std.file;
import std.parallelism;
import std.range;
import std.typecons;

import ae.sys.data;
import ae.sys.datamm;
import ae.sys.file;
import ae.utils.array;
import ae.utils.math.combinatorics;
import ae.utils.math.mixed_radix;
import ae.utils.meta;

import game;

// ------------------------- Items

private struct WithMax(T, T max_)
{
	this(PrePackedGameField value) in(value >= 0 && value <= max_) { this.value = cast(T)value; }
	T value;
	alias value this;
	enum T max = max_;
}

alias PackedShellCount = WithMax!(ubyte, 4);

alias PackedItem = ubyte;
enum packedItemCard = 1 + enumLength!Item; // add 1 for "empty"
alias PackedItemsBase = ushort;
static immutable itemBinomials = BinomialCoefficientTable!(PackedItemsBase, packedItemCard + maxItems, maxItems).generate();
alias ItemCNS = CNS!(PackedItemsBase, PackedItem, maxItems, packedItemCard, /*lexicographic:*/false, /*multiset:*/true, itemBinomials);
// multisetCoefficient(packedItemCard, maxItems) == C(packedItemCard + maxItems - 1, maxItems).
// With the original 5 item types, packedItemCard was 6, giving C(13,8) == 1287.
// With 9 item types (Inverter, Burner Phone, Adrenaline, Expired Medicine added),
// packedItemCard is 10, giving C(17,8) == 24310. This MUST be kept in sync with
// enumLength!Item; if you add/remove items, recompute this (e.g. via
// `math.comb(packedItemCard + maxItems - 1, maxItems)` in Python) and update it here.
enum packedItemsCard = 24310; // == multisetCoefficient(packedItemCard, maxItems) == ItemCNS.packedCard
static assert(packedItemsCard == ItemCNS.packedCard, "packedItemsCard is out of sync with ItemCNS.packedCard - update the hardcoded value above");
alias PackedItems = WithMax!(PackedItemsBase, packedItemsCard - 1);

alias PackedHealth = WithMax!(ubyte, 3); // min == 1 !

enum PackedHandcuffState : ubyte { none, otherWillSkip, otherWillBreak }
immutable HandcuffState[2][enumLength!PackedHandcuffState] packedHandcuffStates = [
	/* [current, other] */
	[HandcuffState.none, HandcuffState.none],
	[HandcuffState.none, HandcuffState.willSkip],
	[HandcuffState.none, HandcuffState.willBreak],
];

enum PackedNextShell : ubyte { unknown, blank, live }
immutable Nullable!ShellType[enumLength!PackedNextShell] packedNextShell = [
	Nullable!ShellType.init,
	ShellType.blank.nullable,
	ShellType.live.nullable,
];

// Burner Phone's pending reveal: either nothing pending (index 0), or a shell
// type plus how many undetermined draws remain before it comes up (1 .. maxShells).
// Packed as: 0 = none; otherwise 1 + shellType * maxShells + (countdown - 1).
enum packedFutureShellCard = 1 + enumLength!ShellType * maxShells;
alias PackedFutureShell = WithMax!(ubyte, packedFutureShellCard - 1);

PackedFutureShell packFutureShell(Nullable!ShellType shell, ubyte countdown) nothrow @nogc
{
	if (shell.isNull)
		return PackedFutureShell(cast(PrePackedGameField)0);
	return PackedFutureShell(cast(PrePackedGameField)(1 + shell.get() * maxShells + (countdown - 1)));
}

Tuple!(Nullable!ShellType, "shell", ubyte, "countdown") unpackFutureShell(PackedFutureShell packed) nothrow @nogc
{
	if (packed == 0)
		return typeof(return)(Nullable!ShellType.init, cast(ubyte)0);
	auto v = packed.value - 1;
	return typeof(return)((cast(ShellType)(v / maxShells)).nullable, cast(ubyte)(v % maxShells + 1));
}

struct PrePackedGame
{
	Character currentTurn;
	PackedShellCount[enumLength!ShellType] shells;

	// (we could save 226491/1679616 (~13%) if we make >2 cigarette packs unrepresentable...)
	PackedItems[enumLength!Character] items;
	PackedHealth[enumLength!Character] health;
	PackedHandcuffState handcuffs;
	PackedNextShell nextShell;
	PackedFutureShell futureShell;
	bool shotgunSawedOff;
	bool chamberInverted;
	WithMax!(ubyte, maxShells) dealerPhoneCandidates;
	bool dealerPhoneExcluded;

	static PackedItems packItems(byte[enumLength!Item] items) nothrow @nogc
	{
		PackedItem[maxItems] packedItems;
		size_t i = maxItems;
		foreach_reverse (Item itemType; Item.init .. enumLength!Item)
			foreach (j; 0 .. items[itemType])
				packedItems[--i] = cast(ubyte)(1 + itemType);
		packedItems[0 .. i] = 0;
		PackedItems result = ItemCNS.pack(packedItems);
		return result;
	}

	static byte[enumLength!Item] unpackItems(PackedItems p) nothrow @nogc
	in (p < packedItemsCard)
	{
		PackedItem[maxItems] packedItems = ItemCNS.unpack(p);
		byte[enumLength!Item] result;
		foreach (packedItem; packedItems)
			if (packedItem > 0)
				result[cast(Item)(packedItem - 1)]++;
		return result;
	}

	this(Game game) nothrow @nogc
	{
		this.currentTurn = game.currentTurn;
		foreach (i, value; game.shells) this.shells[i] = value;
		foreach (i, value; game.items) this.items[i] = packItems(value);
		foreach (i, value; game.health) this.health[i] = cast(ubyte)(value - 1);
		this.handcuffs = cast(PackedHandcuffState)packedHandcuffStates.indexOf([
			game.handcuffs[game.currentTurn      ],
			game.handcuffs[game.currentTurn.other]
		].staticArray);
		this.nextShell = cast(PackedNextShell)packedNextShell.indexOf(game.nextShell);
		this.futureShell = packFutureShell(game.futureShell, game.futureShellCountdown);
		this.shotgunSawedOff = game.shotgunSawedOff;
		this.chamberInverted = game.chamberInverted;
		this.dealerPhoneCandidates = game.dealerPhoneCandidates;
		this.dealerPhoneExcluded = game.dealerPhoneExcluded;
	}

	Game unpack() nothrow @nogc
	{
		Game game;
		game.currentTurn = this.currentTurn;
		foreach (i, value; this.shells) game.shells[i] = value;
		foreach (i, value; this.items) game.items[i] = unpackItems(value);
		foreach (i, value; this.health) game.health[i] = cast(ubyte)(value + 1);
		game.handcuffs[game.currentTurn      ] = packedHandcuffStates[this.handcuffs][0];
		game.handcuffs[game.currentTurn.other] = packedHandcuffStates[this.handcuffs][1];
		game.nextShell = packedNextShell[this.nextShell];
		{
			auto f = unpackFutureShell(this.futureShell);
			game.futureShell = f.shell;
			game.futureShellCountdown = f.countdown;
		}
		game.shotgunSawedOff = this.shotgunSawedOff;
		game.chamberInverted = this.chamberInverted;
		game.dealerPhoneCandidates = this.dealerPhoneCandidates;
		game.dealerPhoneExcluded = this.dealerPhoneExcluded;
		return game;
	}
}

alias PrePackedGameField = ushort; // biggest pre-packed game field
alias PackedGame = ulong;

alias GameSerializer = SerializationCoder!(MixedRadixCoder!(PrePackedGameField, PackedGame), PrePackedGame);

static assert(GameSerializer.minValue == 0);
immutable PackedGame packedGameCard = GameSerializer.cardinality;

PackedGame packGame(Game game) nothrow @nogc { return GameSerializer.serialize(PrePackedGame(game)); }
Game unpackGame(PackedGame packed) nothrow @nogc { return GameSerializer.deserialize(packed).unpack(); }


version (main_packing)
void main()
{
	import std.stdio: stderr;

	// foreach (i; 0 .. packedGameCard)
	// {
	// 	if (i % 100_000 == 0) stderr.writeln(i, " / ", packedGameCard);
	// 	assert(i.unpackGame().packGame() == i);
	// }

	// while (true)
	// {
	// 	import std.random : uniform;
	// 	auto i = uniform(0, packedGameCard);
	// 	if (i % 100_000 == 0) stderr.writeln(i, " / ", packedGameCard);
	// 	assert(i.unpackGame().packGame() == i);
	// }

	while (true)
	{
		import std.random : uniform;
		import expand : expand, Score, Opponent, graphChoice, scoreIndeterminate;

		auto i = uniform(0, packedGameCard);
		if (i % 100_000 == 0) stderr.writeln(i, " / ", packedGameCard);
		auto game = i.unpackGame();

		struct Driver
		{
			enum interactive = false;
			void log(scope string delegate() message) nothrow @nogc {}

			Score recurse(const ref Game game) nothrow @nogc
			{
				assert(game.packGame().unpackGame() == game);
				return scoreIndeterminate;
			}

			alias choice = graphChoice;
			alias gameOver = graphGameOver;
		}
		auto driver = Driver();

		scope(failure) stderr.writeln(game);
		expand(game, driver, Opponent.init);
	}
}
