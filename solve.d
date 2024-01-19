import std.algorithm.iteration;
import std.stdio;

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

struct Game
{
	Character currentTurn;
	int[enumLength!RoundType] rounds;
	@property uint totalRounds() const { return rounds[].sum; }
	int[enumLength!Character] health;
}

enum Move
{
	shootSelf,
	shootOther,
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

SearchResult search(const ref Game game)
{
	Score shoot(Character whom)
	{
		Score totalScore = 0;
		foreach (roundType; RoundType.init .. enumLength!RoundType)
			if (game.rounds[roundType])
			{
				auto score = {
					Game newGame = game;
					newGame.rounds[roundType]--;
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
					if (newGame.totalRounds == 0)
					{
						// Refill magazine. TODO: better distribution, or even iterate?
						newGame.rounds[] = 2;
					}
					return search(newGame).score;
				}();
				auto prob = double(game.rounds[roundType]) / game.totalRounds;
				totalScore += score * prob;
			}
		return totalScore;
	}

	Score tryMove(Move move)
	{
		final switch (move)
		{
			case Move.shootSelf : return shoot(game.currentTurn);
			case Move.shootOther: return shoot(game.currentTurn.other);
		}
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
