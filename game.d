import std.algorithm.iteration;
import std.typecons;

import ae.utils.meta;

enum Character : ubyte
{
	player,
	dealer,
}

Character other(Character character) nothrow @nogc { return cast(Character)(1 - character); }

enum ShellType : ubyte
{
	blank,
	live,
}

enum Item : ubyte
{
	lookingGlass,
	handcuffs,
	beer,
	cigarettePack,
	handSaw,
}

enum maxShells = 8;
enum maxItems = 8;

enum HandcuffState
{
	none,
	willBreak,
	willSkip,
}

struct Game
{
	Character currentTurn;
	byte[enumLength!ShellType] shells;
	@property uint totalShells() const nothrow @nogc { return shells[].sum + (nextShell.isNull ? 0 : 1); }
	byte[enumLength!Item][enumLength!Character] items;
	uint totalItems(Character character) const nothrow @nogc { return items[character][].sum; }
	byte[enumLength!Character] health;
	HandcuffState[enumLength!Character] handcuffs;
	Nullable!ShellType nextShell;
	bool shotgunSawedOff;
}

