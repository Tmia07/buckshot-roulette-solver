import std.algorithm.iteration;
import std.typecons;

import ae.utils.meta;

enum Character
{
	player,
	dealer,
}

Character other(Character character) { return cast(Character)(1 - character); }

enum ShellType : ubyte
{
	blank,
	live,
}

enum Item
{
	lookingGlass,
	handcuffs,
	beer,
	cigarettePack,
	handSaw,
}

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
	@property uint totalShells() const { return shells[].sum + (nextShell.isNull ? 0 : 1); }
	byte[enumLength!Item][enumLength!Character] items;
	byte[enumLength!Character] health;
	HandcuffState[enumLength!Character] handcuffs;
	Nullable!ShellType nextShell;
	bool shotgunSawedOff;
}

