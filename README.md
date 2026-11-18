# Buckshot Roulette solver

A solver for [Buckshot Roulette](https://store.steampowered.com/app/2835570/): enter a
position and it shows your chance to win for every move, assuming perfect play on your
side, against either the game's Dealer AI or a perfect opponent.

Based on the original solver by **Vladimir Panteleev (CyberShadow)**:
<https://gist.github.com/CyberShadow/87d403bb29fa3047f2182c41f74e286e>.
The original history is on the [`original`](../../tree/original) branch.
Thanks to the author for licensing it under BSL-1.0.

## What's new compared to the original

- **Current item set:** Inverter, Burner Phone, Adrenaline and Expired Medicine.
- **No precomputed table needed.** With 9 item types the full score table would have
  ~10^14 entries, so scores are computed on the fly: exactly within a round, with
  time-limited (8 s) iterative deepening for very complex positions. The start of a new
  round is estimated from health; analysis stops at the end of a round.
- **Hidden information** is modelled from the player's point of view: an Inverter used on
  an unknown shell is not revealed, and you don't learn what the dealer's Burner Phone said.
- **UI:** item picker list, the explorer keeps your place when you change a choice.
- **Live mode** (optional): follows a single-player game automatically through a small
  in-game bridge, see [`bridge/README.md`](bridge/README.md). No game files are included.

## Building (Windows)

Requirements: [DMD](https://dlang.org/download.html) (tested with 2.112) and the OpenSSL
import libraries `ssl.lib` and `crypto.lib` in the repository root (needed by the `ae`
networking code that the solver links against).

```
build.bat
```

This produces `websolver.exe`. (`dmd -O` hits a false "null dereference" error in the JSON
code, so `build.bat` optimizes only the solver core.)

## Running

Any PHP 8 works:

```
php -S 127.0.0.1:8000
```

and open <http://127.0.0.1:8000>. Use `127.0.0.1` rather than `localhost` if you use the
Live mode (on Windows `localhost` may bind to IPv6 only).

## License

BSL-1.0, see [LICENSE](LICENSE). Vendored dependencies (`ae/`, `deimos/`) keep their own
licenses.
