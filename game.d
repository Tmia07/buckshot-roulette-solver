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
	magnifyingGlass,
	handcuffs,
	beer,
	cigarettePack,
	handSaw,
	inverter,
	burnerPhone,
	adrenaline,
	expiredMedicine,
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

	/// Set by Burner Phone: the type of a shell further ahead than `nextShell`
	/// (i.e. not the very next one to be racked/fired).
	Nullable!ShellType futureShell;
	/// Number of yet-undetermined draws from `shells` that must happen
	/// before `futureShell` comes up. Only meaningful while `futureShell`
	/// is non-null; always >= 1 while pending, reaches 0 once resolved.
	ubyte futureShellCountdown;

	/// The chambered shell (type unknown to the player) was flipped with an
	/// Inverter. Its type is decided only when it is fired / revealed, so the
	/// player's decisions in between cannot depend on it.
	bool chamberInverted;

	/// The dealer used a Burner Phone: they know one of the upcoming shells,
	/// but the player does not know which one or what it is.
	/// Number of upcoming shells that may be the revealed one (0 = none).
	ubyte dealerPhoneCandidates;
	/// The currently chambered shell is known not to be the revealed one.
	bool dealerPhoneExcluded;
}

