import std.algorithm.iteration;
import std.stdio;
import std.typecons;

import ae.utils.meta;

enum Character
{
	player,
	dealer,
}

Character other(Character character) { return cast(Character)(1 - character); }

enum RoundType
{
	blank,
	live,
}

enum Item
{
	lookingGlass,
	handcuffs,
	beer,
}

struct Game
{
	Character currentTurn;
	byte[enumLength!RoundType] rounds;
	@property uint totalRounds() const { return rounds[].sum; }
	byte[enumLength!Item][enumLength!Character] items;
	byte[enumLength!Character] health;
	byte[enumLength!Character] handcuffs;
	Nullable!RoundType nextRound;
}

enum Move
{
	shootSelf,
	shootOther,
	useLookingGlass,
	useHandcuffs,
	useBeer,
}

alias Score = double;

enum loseScore = 0;
enum winScore = 1;
enum healthScoreBonus = 0.1;

struct SearchResult
{
	Score score;
	Move bestMove;
}

SearchResult[Game] searchCache;
SearchResult search(const ref Game game)
{
	return searchCache.require(game, searchImpl(game));
}

SearchResult searchImpl(const ref Game game)
{
	Score resolveRound(const ref Game game, scope Score delegate(RoundType roundType, ref Game newGame) handler)
	{
		if (!game.nextRound.isNull)
		{
			Game newGame = game;
			auto roundType = newGame.nextRound.get();
			newGame.nextRound.nullify();
			return handler(roundType, newGame);
		}

		Score totalScore = 0;
		foreach (roundType; RoundType.init .. enumLength!RoundType)
			if (game.rounds[roundType])
			{
				auto score = {
					Game newGame = game;
					newGame.rounds[roundType]--;
					return handler(roundType, newGame);
				}();
				auto prob = double(game.rounds[roundType]) / game.totalRounds;
				totalScore += score * prob;
			}
		return totalScore;
	}

	Score shoot(Character whom)
	{
		return resolveRound(game, (RoundType roundType, ref Game newGame) {
			final switch (roundType)
			{
				case RoundType.blank:
					// If the shotgun was aimed at the other player, switch turns
					if (whom != newGame.currentTurn)
						newGame.currentTurn = newGame.currentTurn.other;
					break;
				case RoundType.live:
					newGame.health[whom]--;
					if (newGame.health[whom] <= 0)
						final switch (whom)
						{
							case Character.player:
								return loseScore;
							case Character.dealer:
								return winScore + newGame.health[Character.player] * healthScoreBonus;
						}
					newGame.currentTurn = newGame.currentTurn.other;
					break;
			}
			return search(newGame).score;
		});
	}

	Score use(Item item)
	{
		if (!game.items[game.currentTurn][item])
			return Score.nan;
		Game newGame = game;
		newGame.items[game.currentTurn][item]--;
		final switch (item)
		{
			case Item.handcuffs:
				newGame.handcuffs[newGame.currentTurn.other]++;
				return search(newGame).score;
			case Item.lookingGlass:
				if (!newGame.nextRound.isNull)
					return Score.nan;
				return resolveRound(newGame, (RoundType roundType, ref Game newGame) {
					newGame.nextRound = roundType;
					return search(newGame).score;
				});
			case Item.beer:
				return resolveRound(newGame, (RoundType roundType, ref Game newGame) {
					cast(void)roundType; // CAST IT INTO THE VOID
					return search(newGame).score;
				});
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
		}
	}

	if (game.totalRounds == 0)
	{
		// Refill magazine. TODO: better distribution, or even iterate?
		Game newGame = game;
		newGame.rounds[] = 2;
		return search(newGame);
	}

	if (game.handcuffs[game.currentTurn])
	{
		Game newGame = game;
		newGame.handcuffs[game.currentTurn]--;
		newGame.currentTurn = newGame.currentTurn.other;
		return search(newGame);
	}

	final switch (game.currentTurn)
	{
		case Character.player:
			// Assume that the player will proceed according to what's best for them.
			auto bestResult = SearchResult(-Score.infinity);
			foreach (move; Move.init .. enumLength!Move)
			{
				auto score = tryMove(move);
				if (score > bestResult.score)
					bestResult = SearchResult(score, move);
			}
			return bestResult;

		case Character.dealer:
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
}

void main()
{
	Game game;
	game.currentTurn = Character.player;
	game.rounds[RoundType.blank] = 2;
	game.rounds[RoundType.live] = 1;
	game.health[Character.player] = 2;
	game.health[Character.dealer] = 2;

	writeln(search(game));
}
