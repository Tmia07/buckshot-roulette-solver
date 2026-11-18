const defaultGame = {
	currentTurn: 'player',
	shells: ['live', 'live', 'blank', null, null, null, null, null],
	items: [
		[null, null, null, null, null, null, null, null],
		[null, null, null, null, null, null, null, null]
	],
	nextShell: null,
	futureShell: null, // Додано для Телефону
	futureShellCountdown: 0, // Додано для Телефону
	health: [2, 2],
	handcuffs: [null, null],
	shotgunSawedOff: false,
};

let currentGame = copyGame(defaultGame);
let showGameFuncs = [];
let resetGameFuncs = [];

function showGame(game) {
	document.querySelectorAll('.value').forEach(e => e.remove());
	document.querySelectorAll('.error').forEach(e => e.style.removeProperty('fill'));
	document.body.classList.toggle('packed-game', typeof game === 'string');
	if (typeof game === 'string')
		document.getElementById('packed-game').textContent = 'Game #' + game;
	else {
		for (let func of showGameFuncs)
			func(game);
		showHiddenState(game);
	}
}

function showHiddenState(game) {
	const box = document.getElementById('hidden-state');
	const lines = [];
	if (game.chamberInverted)
		lines.push(['chamberInverted', '🔃 The chambered shell was flipped with an Inverter (its type is unknown).']);
	if (game.dealerPhoneCandidates)
		lines.push(['dealerPhoneCandidates', '📱 The dealer knows one of the upcoming shells (from their Burner Phone).']);
	box.replaceChildren(...lines.map(([key, text]) => {
		const clear = node('BUTTON', { type: 'button', title: 'Forget this' }, '✖');
		clear.addEventListener('click', () => {
			delete currentGame[key];
			if (key === 'dealerPhoneCandidates')
				delete currentGame.dealerPhoneExcluded;
			handleGameEdit(true);
		});
		return node('DIV', {}, [text + ' ', clear]);
	}));
	box.style.display = lines.length ? 'block' : 'none';
}

function copyGame(game) { return JSON.parse(JSON.stringify(game)); }

function flipBoard() {
	let game = copyGame(currentGame);
	game.currentTurn = game.currentTurn == 'player' ? 'dealer' : 'player';
	game.items.reverse();
	game.items[0].reverse();
	game.items[1].reverse();
	game.health.reverse();
	game.handcuffs.reverse();
	currentGame = game;
}

function resetBoard() {
	for (let func of resetGameFuncs)
		func(currentGame);
}

const winPercentFormatter = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  style: 'percent'
});
const choiceProbabilityFormatter = new Intl.NumberFormat('en-US', {
  maximumFractionDigits: 0,
  style: 'percent'
});

var choiceCounter = 0;

function node(tagName, attributes, children) {
	let e = document.createElement(tagName);
	if (typeof attributes !== 'undefined')
		for (let name in attributes)
			e.setAttribute(name, attributes[name]);
	if (typeof children !== 'undefined') {
		if (typeof children === 'string')
			e.textContent = children;
		else {
			if (!Array.isArray(children))
				children = [children];
			for (let child of children) {
				if (typeof child === 'string')
					child = document.createTextNode(child);
				e.appendChild(child);
			}
		}
	}
	return e;
}

function addAnalysis(problem, data) {
	const origProblem = problem;
	const explorerHeader = document.getElementById('explorer-header');
	while (explorerHeader.nextSibling)
		explorerHeader.nextSibling.remove();

	function addEvent(icon, text, winPercent) {
		const tr = node('TR', {}, [
			node('TD', {}, icon),
			node('TD', {}, text),
			node('TD', {}, winPercent === undefined || winPercent === null
				 ? undefined
				 : winPercentFormatter.format(winPercent)
			)
		]);
		explorerHeader.parentElement.appendChild(tr);
		return tr;
	}

	function gameLink(o) {
		const link = node('A', {href: '#' + o.packedGame + '/' + problem.opponent}, 'Game #' + o.packedGame);
		link.addEventListener('click', function(e) {
			e.preventDefault();
			document.getElementById('explorer-page').scrollTo({ top: 0, behavior: 'smooth' });

			currentGame = copyGame(o.game);
			handleGameEdit(true);
		});
		return link;
	}

	if ('error' in data) {
		addEvent('💥', 'Fatal error: ' + data.error);
		document.getElementById('summary').replaceChildren(node('DIV', {}, [node('B', {}, 'Summary:'), ' ', 'Error, please see below.']));
		return;
	}
	if ('validationError' in data) {
		addEvent('💥', 'Invalid game: ' + data.validationError.message);
		for (let id of data.validationError.ids) {
			let e = document.getElementById('slot-' + id);
			e.classList.add('error');
			e.style.fill = '#faa';
		}
		document.getElementById('summary').replaceChildren(node('DIV', {}, [node('B', {}, 'Summary:'), ' ', 'Error, please see below.']));
		return;
	}

	for (let event of data.events) {
		if ('message' in event)
			addEvent('ℹ️', event.message);
		else
		if ('start' in event)
			addEvent('🚀', ['Analyzing ', gameLink(data), '.'], event.start);
		else
		if ('choice' in event) {
			choiceCounter++;
			let icon =
				event.choice.mode == 'best' ? '🤔' :
				event.choice.mode == 'worst' ? '🖥️' :
				event.choice.mode == 'random' ? '🎲' :
				event.choice.mode == 'randomWithDuplicates' ? '🎲' :
				event.choice.mode == 'unknown' ? '❓' :
				event.choice.mode == 'first' ? '❓' :
				'';
			const choiceRow = addEvent(icon,
					 event.choice.description,
					 event.choice.score);
			for (let i = 0; i < event.choice.options.length; i++) {
				let option = event.choice.options[i];
				let description = option.description;
				if ('probability' in option)
					description = '[' + choiceProbabilityFormatter.format(option.probability) + '] ' + description;
				let radio = node('INPUT', {
					type: 'radio',
					name: 'choice-' + choiceCounter,
					id: 'choice-' + choiceCounter + '-' + i,
					value: i
				});
				if ('selectedOptionIndex' in event.choice && i == event.choice.selectedOptionIndex)
					radio.checked = 'checked';
				let label = node('LABEL', { for: radio.id }, [
					radio,
					description,
				]);
				radio.addEventListener('change', function() {
					// Remember where the changed choice is on screen, so that the view
					// does not jump around after the analysis is recalculated.
					const ep = document.getElementById('explorer-page');
					const rows = [...explorerHeader.parentElement.children];
					scrollAnchor = {
						rowIndex: rows.indexOf(choiceRow),
						offset: choiceRow.getBoundingClientRect().top - ep.getBoundingClientRect().top,
					};
					const problem = {
						opponent: origProblem.opponent,
						game: data.game,
						decisions: option.decisions,
					};
					queryProblem(problem);
				});
				addEvent('➡️', label, option.outcome);
			}
		}
		else
		if ('recursion' in event) {
			addEvent('📍', ['Checkpoint: ', gameLink(event.recursion), '.'], event.recursion.score);
		}
		else
		if ('gameOver' in event) {
			addEvent(event.gameOver ? '✌️' : '💀', 'Game over.', event.gameOver ? 1 : 0);
		}
	}

	restoreScrollAnchor(explorerHeader.parentElement);

	document.getElementById('summary').replaceChildren(node(
		'DIV', {}, [
			node('B', {}, 'Summary:'),
			' ',
		].concat((function() {
			if (data.events.length < 2 || !('start' in data.events[0]))
				return ['Failed to summarize results (unrecognized events).'];
			if ('choice' in data.events[1] && data.events[1].choice.mode === 'best') {
				let bestScore = data.events[1].choice.score;
				let bestOptions = [];
				for (let option of data.events[1].choice.options)
					if (option.outcome === bestScore)
						bestOptions.push(option);
				if (!bestOptions.length)
					return ['Failed to summarize results (no options).'];
				if (bestOptions.length == data.events[1].choice.options.length)
					return [
						"It's your turn, however, at this point, your choice ", node('B', {}, "does not matter"), ". ",
						"No matter what you do now, you have a ", node('B', {}, winPercentFormatter.format(bestScore)), " chance to win."
					];
				else {
					const interleave = (arr, thing) => [].concat(...arr.map(n => [n, thing])).slice(0, -1);
					return [
						"It's your turn. For the best outcome (", node('B', {}, winPercentFormatter.format(bestScore)), "), you should ",
					].concat(interleave(bestOptions.map(option => node('B', {}, option.description)), ' or ')).concat(["."]);
				}
			} else {
				return ["It is currently not your turn, but in this situation, you have a ", node('B', {}, winPercentFormatter.format(data.events[0].start)), " chance to win."];
			}
		})()),
	));
}

let scrollAnchor = null;

function restoreScrollAnchor(table) {
	const ep = document.getElementById('explorer-page');
	table.style.marginBottom = '';
	if (!scrollAnchor)
		return;
	const anchor = scrollAnchor;
	scrollAnchor = null;
	const row = table.children[anchor.rowIndex];
	if (!row)
		return;
	let delta = row.getBoundingClientRect().top - ep.getBoundingClientRect().top - anchor.offset;
	// If the new line of play is shorter, add space below so the row can stay in place.
	const maxScroll = ep.scrollHeight - ep.clientHeight;
	if (ep.scrollTop + delta > maxScroll)
		table.style.marginBottom = (ep.scrollTop + delta - maxScroll) + 'px';
	ep.scrollTop += delta;
	row.classList.remove('flash');
	void row.offsetWidth; // restart animation
	row.classList.add('flash');
}

let stateVersion = 0;

function queryProblem(problem, delay, noSave) {
	let requestVersion = ++stateVersion;

	if (delay === undefined)
		delay = 0;
	
	currentGame = 'game' in problem ? copyGame(problem.game) : problem.packedGame;
	showGame(currentGame);

	document.getElementById('opponent').value = 'opponent' in problem ? problem.opponent : 'game';

	setTimeout(function() {
		if (requestVersion != stateVersion)
			return; // outdated
		if (dragging)
			return;

		// const state = save();
		// const hash = '#' + state;
		// if (hash != window.location.hash)
		// 	window.location = hash;  // Push state

		document.body.classList.toggle('loading', true);

		const url = window.location.hostname == 'cy.md'
			  ? 'https://home.cy.md/jsonapi/backshot-roulette-solver'
			  : 'websolver.php';
		fetch(url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify(problem),
		})
		.then((response) => response.ok ? response.json() : { error: "HTTP " + response.status })
		.then((data) => {
			if (requestVersion != stateVersion)
				return; // outdated
			if (dragging)
				return;
			if ('game' in data) {
				currentGame = copyGame(data.game);
				showGame(currentGame);
			}
			addAnalysis(problem, data);
			if ('game' in data && 'packedGame' in data) {
				problem.game = data.game;
				problem.packedGame = data.packedGame;
				if (noSave)
					window.history.replaceState(problem, '', '#' + serialize(problem));
				else
					window.history.pushState(problem, '', '#' + serialize(problem));
			}
			document.body.classList.toggle('loading', false);
		})
		.catch((error) => {
			if (requestVersion != stateVersion)
				return; // outdated
			console.log(error);
			document.body.classList.toggle('loading', false);
			// document.getElementById('status-error').style.display = 'flex';
			document.getElementById('summary').textContent = 'Error: ' + error;
		});
	}, delay);
}

function serialize(problem) {
	let result = problem.packedGame + '/' + problem.opponent;
	if ('decisions' in problem)
		result += '/' + problem.decisions.map(n => n.toString()).join(',');
	return result;
}

function deserialize(hash) {
	let parts = hash.split('/');
	let result = {};
	if (parts.length > 0)
		result.packedGame = parts[0];
	if (parts.length > 1)
		result.opponent = parts[1];
	else
		result.opponent = 'game';
	if (parts.length > 2)
		result.decisions = parts[2].split(',').map(n => parseInt(n));
	return result;
}

window.addEventListener('popstate', function(e) {
	let problem;
	if (e.state !== null)
		problem = e.state;
	else if (window.location.hash.length > 1)
		problem = deserialize(window.location.hash.substr(1));
	else
		return;
	loadProblem(problem);
});

// Replaces the current history state. Use after navigation.
function loadProblem(problem) {
	queryProblem(problem, 0, true);
}

// Use this for interactive edits. It creates a new problem, with no decisions.
function handleGameEdit(now) {
	// for (const id of ['status-badinput', 'status-loading', 'status-nodie', 'status-error', 'result-0', 'result-1', 'result-2', 'opp-move-0', 'opp-move-1', 'opp-move-2'])
	// 	document.getElementById(id).style.display = 'none';

	const problem = {
		opponent: document.getElementById('opponent').value,
		[typeof currentGame === 'string' ? 'packedGame' : 'game']: currentGame
	};
	queryProblem(problem, now ? 0 : 500);
}


// ----- Item picker (a list instead of cycling through values)

function itemLabel(type, value) {
	if (value === null)
		return { icon: '✖️', name: 'Empty' };
	const def = document.getElementById(type + '-' + value);
	return {
		icon: def && def.querySelector('text') ? def.querySelector('text').textContent : '',
		name: def && def.querySelector('title') ? def.querySelector('title').textContent : value,
	};
}

function closePicker() {
	const old = document.getElementById('picker');
	if (old)
		old.remove();
}

function openPicker(event, labels, selectedIndex, onPick) {
	closePicker();
	const picker = node('DIV', { id: 'picker' });
	labels.forEach((label, index) => {
		const button = node('BUTTON', { type: 'button' }, [
			node('SPAN', { class: 'emoji' }, label.icon),
			' ' + label.name,
		]);
		if (index === selectedIndex)
			button.classList.add('selected');
		button.addEventListener('click', e => {
			e.stopPropagation();
			closePicker();
			onPick(index);
		});
		picker.appendChild(button);
	});
	document.body.appendChild(picker);
	// Position near the cursor, but keep it inside the window.
	const w = picker.offsetWidth, h = picker.offsetHeight;
	picker.style.left = Math.max(4, Math.min(event.clientX, window.innerWidth - w - 4)) + 'px';
	picker.style.top = Math.max(4, Math.min(event.clientY, window.innerHeight - h - 4)) + 'px';
}

document.addEventListener('pointerdown', e => {
	const picker = document.getElementById('picker');
	if (picker && !picker.contains(e.target))
		closePicker();
}, true);
document.addEventListener('keydown', e => { if (e.key === 'Escape') closePicker(); });

// Note: The HTML drag and drop API (dragstart / dragover / drop) does not work on SVG elements.

var dragging = false;
var lastDropTarget = null;

function makeDraggable(node, data, handleFeedback) {
	function getDropTarget(e) {
		for (let target of document.elementsFromPoint(e.clientX, e.clientY)) {
			// console.log('CHECKING IF CAN DROP OVER ', target);

			if ('myIsDroppable' in target && target.myIsDroppable(data))
				return target;
		}
		// console.log('CANNOT DROP OVER ANYTHING');
		return null;
	}

	let primed = false; // per-node
	node.addEventListener('pointerdown', e => {
		e.preventDefault();
		primed = true;
	});
	node.addEventListener('pointermove', e => {
		e.preventDefault();
		if (primed && !dragging && e.buttons == 1) {
			// console.log('DRAG START');
			primed = false;
			dragging = true;
			node.setPointerCapture(e.pointerId);
			handleFeedback(true);
		}
		if (dragging) {
			// console.log('DRAGGING OVER ', document.elementsFromPoint(e.clientX, e.clientY));
			let target = getDropTarget(e);
			if (target !== lastDropTarget) {
				if (lastDropTarget)
					lastDropTarget.myHandleFeedback(false);
				if (target)
					target.myHandleFeedback(true);
				lastDropTarget = target;
			}
		}
	});
	node.addEventListener('pointerup', e => {
		e.preventDefault();
		primed = false;
		if (dragging) {
			// console.log('DRAGGING END');
			node.releasePointerCapture(e.pointerId);
			e.stopImmediatePropagation();
			if (lastDropTarget)
				lastDropTarget.myHandleFeedback(false);
			handleFeedback(false);
			setTimeout(() => {
				dragging = false;
			}, 0);

			let target = getDropTarget(e);
			if (target)
				target.myHandleDropped(data);
		}
	});
}

function makeDropTarget(slotNode, isDroppable, handleDropped, handleFeedback) {
	slotNode.myIsDroppable = isDroppable;
	slotNode.myHandleDropped = handleDropped;
	slotNode.myHandleFeedback = handleFeedback;
}


document.addEventListener('DOMContentLoaded', function() {
	let dragged = null;

	function addControl(type, slot, path, values, valueIDs) {
		let slotID = 'slot-' + type + (slot !== null ? '-' + slot : '');
		let slotNode = document.getElementById(slotID);
		slotNode.style.cursor = 'pointer';

		function getValue(game) {
			let v = game;
			for (let step of path)
				v = v[step];
			return v;
		}
		function setValue(game, value) {
			let v = game;
			for (let step of path.slice(0, -1))
				v = v[step];
			v[path[path.length-1]] = value;
		}

		function cycleValue(game, indexUpdateFun) {
			let oldValue = getValue(game);
			let oldValueIndex = values.indexOf(oldValue);
			let newValueIndex = indexUpdateFun(oldValueIndex);
			newValueIndex = (newValueIndex + values.length) % values.length;
			let newValue = values[newValueIndex];
			setValue(game, newValue);

			handleGameEdit();
		}

		slotNode.addEventListener('click', function(event) {
			if (!dragging && event.button == 0) {
				if (type === 'item')
					openPicker(event, values.map(v => itemLabel(type, v)), values.indexOf(getValue(currentGame)), index => {
						setValue(currentGame, values[index]);
						handleGameEdit(true);
					});
				else
					cycleValue(currentGame, index => index + 1);
				event.preventDefault();
			}
		});
		slotNode.addEventListener('wheel', function(event) {
			cycleValue(currentGame, index => index + Math.sign(event.deltaX + event.deltaY));
			event.preventDefault();
		});
		slotNode.addEventListener('contextmenu', function(event) {
			cycleValue(currentGame, index => 0);
			event.preventDefault();
		});

		const bg = slotNode.querySelector('.bg');
		makeDropTarget(
			bg,
			dragged => dragged.type === type && dragged.slot !== slot,
			dragged => {
				let v0 = getValue(currentGame);
				let v1 = dragged.getValue(currentGame);

				setValue(currentGame, v1);
				dragged.setValue(currentGame, v0);

				handleGameEdit();
			},
			isTarget => bg.classList.toggle('drop-target', isTarget),
		);

		showGameFuncs.push((game) => {
			let value = getValue(game);
			let valueIndex = values.indexOf(value);
			if (typeof valueIDs === 'function')
				valueIDs(value);
			else {
				let valueID = valueIDs[valueIndex];
				if (valueID !== null) {
					valueID = type + '-' + valueID;

					let valueNode = document.createElementNS("http://www.w3.org/2000/svg", 'use');
					valueNode.classList.add('value');
					valueNode.setAttributeNS("http://www.w3.org/1999/xlink", 'href', '#' + valueID);
					slotNode.appendChild(valueNode);

					makeDraggable(
						valueNode,
						{type, slot, getValue, setValue},
						isDragged => {
							valueNode.classList.toggle('dragged', isDragged);
							// console.log(isDragged, valueNode);
						},
					);
				}
			}
		});

		resetGameFuncs.push((game) => {
			cycleValue(game, index => 0);
		});
	}
	addControl('handle', null, ['currentTurn'], ['player', 'dealer'], (currentTurn) => {
		let e = document.getElementById('board');
		e.classList.toggle('dealer-turn', currentTurn === 'dealer');
	});
	for (let i = 0; i < defaultGame.shells.length; i++)
		addControl('shell', i, ['shells', i], [null, 'blank', 'live'], [null, 'blank', 'live']);
	addControl('shell', 'next', ['nextShell'], [null, 'blank', 'live'], ['unknown', 'blank', 'live']);
for (let c = 0; c < defaultGame.items.length; c++)
		for (let i = 0; i < defaultGame.items[c].length; i++)
			addControl('item', c + '-' + i, ['items', c, i],
					   [null, 'magnifyingGlass', 'handcuffs', 'beer', 'cigarettePack', 'handSaw', 'inverter', 'burnerPhone', 'adrenaline', 'expiredMedicine'],
					   [null, 'magnifyingGlass', 'handcuffs', 'beer', 'cigarettePack', 'handSaw', 'inverter', 'burnerPhone', 'adrenaline', 'expiredMedicine']);
	for (let c = 0; c < defaultGame.health.length; c++)
		addControl('health', c, ['health', c], [4, 3, 2, 1], ['4', '3', '2', '1']);
	for (let c = 0; c < defaultGame.handcuffs.length; c++)
		addControl('handcuffs', c, ['handcuffs', c],
				   [null, 'willSkip', 'willBreak'],
				   [null, 'willSkip', 'willBreak']);
	addControl('barrel', null, ['shotgunSawedOff'], [false, true], [null, 'cutoff']);

	document.getElementById('button-flip').addEventListener('click', function(e) {
		e.preventDefault();
		flipBoard();
		handleGameEdit(true);
	});

	document.getElementById('button-reset').addEventListener('click', function(e) {
		e.preventDefault();
		resetBoard();
		handleGameEdit(true);
	});

	document.getElementById('opponent').addEventListener('change', function(e) {
		e.preventDefault();
		handleGameEdit(true);
	});

	let problem = null;
	if (window.location.hash.length > 1) {
		try {
			problem = deserialize(window.location.hash.substr(1));
		} catch (e) {
			console.log(e);
		}
	}
	if (!problem)
		problem = {
			game: defaultGame,
			opponent: 'game',
		};
	loadProblem(problem);

	const page = document.getElementById('page');
	const pageStyle = window.getComputedStyle(page);
// 	const numUIColumns = pageStyle.gridTemplateColumns.split(' ').length;
// 	const numUIRows = pageStyle.gridTemplateRows.split(' ').length;  // same as aspect-ratio / #page grid-template
	const haveAspectRatio = 'aspectRatio' in pageStyle;

	function updateSize() {
		// // Work around no support of aspect-ratio CSS property
		// // in Steam's in-page browser
		// if (!haveAspectRatio) {
		// 	const unitSize = Math.min(
		// 		document.documentElement.clientWidth / numUIColumns,
		// 		document.documentElement.clientHeight / numUIRows
		// 	);
		// 	page.style.width = (unitSize * numUIColumns) + 'px';
		// 	page.style.height = (unitSize * numUIRows) + 'px';
		// }

		// Make it so that 2em == one grid tile.
		// (Maybe one day this will be doable in CSS...)
		// page.style.fontSize = (page.clientWidth / 2 / numUIRows) + 'px';
		page.style.fontSize = (page.clientWidth / 48) + 'px';

		window.requestAnimationFrame(updateSize);
	}
	updateSize();

	var helpVisible = false;
	document.getElementById('button-help').addEventListener('click', function(e) {
		e.preventDefault();
		helpVisible = !helpVisible;
		document.body.classList.toggle('help-visible', helpVisible);
		document.querySelector('#button-help text').textContent = helpVisible ? '❌' : 'ℹ️';
		document.getElementById('board').classList.remove('help-nag');
		window.localStorage.setItem('buckshot-roulette-seen-help', '');
	});
	if (window.localStorage.getItem('buckshot-roulette-seen-help') === null)
		document.getElementById('board').classList.add('help-nag');
});


// ----- Live link with the game (SolverBridge.gd in the game -> live.php)

let liveVersion = 0;
let livePolling = false;

function setLive(on) {
	document.getElementById('live').checked = on;
	document.body.classList.toggle('live', on);
	document.getElementById('live-status').textContent = on ? '(waiting for the game...)' : '';
	try { window.localStorage.setItem('buckshot-roulette-live', on ? '1' : ''); } catch (e) {}
	if (on)
		pollLive();
}

function applyLive(d) {
	stateVersion++; // cancel any pending manual query
	const problem = d.problem;
	const data = d.analysis;
	if (!problem || !data)
		return;
	currentGame = copyGame('game' in data ? data.game : problem.game);
	showGame(currentGame);
	document.getElementById('opponent').value = problem.opponent;
	addAnalysis(problem, data);
	document.body.classList.toggle('loading', false);
	if ('game' in data && 'packedGame' in data) {
		problem.game = data.game;
		problem.packedGame = data.packedGame;
		window.history.replaceState(problem, '', '#' + serialize(problem));
	}
	const time = new Date(d.time * 1000).toLocaleTimeString();
	document.getElementById('live-status').textContent = '(from game, ' + time + ')';
}

async function pollLive() {
	const box = document.getElementById('live');
	if (!box || !box.checked || livePolling || dragging)
		return;
	livePolling = true;
	try {
		const response = await fetch('live.php?since=' + liveVersion, { cache: 'no-store' });
		const d = await response.json();
		if (d.version > liveVersion && d.problem) {
			liveVersion = d.version;
			if (document.getElementById('live').checked)
				applyLive(d);
		}
	} catch (e) {
		document.getElementById('live-status').textContent = '(no connection)';
	} finally {
		livePolling = false;
	}
}

setInterval(pollLive, 1000);

document.addEventListener('DOMContentLoaded', function() {
	const box = document.getElementById('live');
	box.addEventListener('change', () => setLive(box.checked));
	let saved = '';
	try { saved = window.localStorage.getItem('buckshot-roulette-live') || ''; } catch (e) {}
	if (saved === '1')
		setLive(true);
});
