import React, { useState, useEffect, useMemo } from "react";
import { Check, Circle, Trash2, RotateCcw, Search, FileText, ClipboardList, ShieldAlert, ChevronRight, Flame, User, Swords, DoorClosed } from "lucide-react";

// ---------------------------------------------------------------------------
// Static case data (classic Clue / Cluedo card set)
// ---------------------------------------------------------------------------
const CATEGORIES = [
  { key: "suspect", label: "Suspect", icon: User, cards: ["Miss Scarlett", "Colonel Mustard", "Mrs. White", "Mr. Green", "Mrs. Peacock", "Professor Plum"] },
  { key: "weapon", label: "Weapon", icon: Swords, cards: ["Candlestick", "Knife", "Lead Pipe", "Revolver", "Rope", "Wrench"] },
  { key: "room", label: "Room", icon: DoorClosed, cards: ["Kitchen", "Ballroom", "Conservatory", "Dining Room", "Billiard Room", "Library", "Lounge", "Hall", "Study"] },
];
const ALL_CARDS = CATEGORIES.flatMap((cat) => cat.cards.map((name) => ({ id: `${cat.key}|${name}`, cat: cat.key, name })));
const TOTAL_DEALT = ALL_CARDS.length - CATEGORIES.length; // 21 - 3 case-file cards = 18
const STORAGE_KEY = "clue-case-file-v1";

const SUSPECT_COLORS = {
  "Miss Scarlett": "bg-red-600",
  "Colonel Mustard": "bg-yellow-600",
  "Mrs. White": "bg-stone-100 ring-1 ring-stone-400",
  "Mr. Green": "bg-emerald-700",
  "Mrs. Peacock": "bg-blue-700",
  "Professor Plum": "bg-purple-700",
};
function SuspectDot({ name, small }) {
  const cls = SUSPECT_COLORS[name];
  if (!cls) return null;
  return <span className={`inline-block rounded-full align-middle shrink-0 ring-1 ring-black/5 ${small ? "w-1.5 h-1.5 mr-1" : "w-2.5 h-2.5 mr-1.5"} ${cls}`} />;
}

const uid = () => Math.random().toString(36).slice(2, 10);

// ---------------------------------------------------------------------------
// Deduction engine — pure function: raw inputs in, full derived board out.
// ---------------------------------------------------------------------------
function deduce(game) {
  const players = game.players;
  const state = {};
  players.forEach((p) => (state[p.id] = {}));

  const setHas = (pid, cid) => { state[pid][cid] = "has"; };
  const setNot = (pid, cid) => { if (state[pid][cid] !== "has") state[pid][cid] = "not"; };

  const me = players.find((p) => p.isMe);
  if (me) {
    ALL_CARDS.forEach((c) => (game.myCards.includes(c.id) ? setHas(me.id, c.id) : setNot(me.id, c.id)));
  }

  const constraints = [];
  game.suggestions.forEach((sugg) => {
    sugg.responses.forEach((r) => {
      if (r.result === "no") {
        sugg.cards.forEach((cid) => setNot(r.playerId, cid));
      } else if (r.result === "yes") {
        if (r.shownCard) setHas(r.playerId, r.shownCard);
        else constraints.push({ playerId: r.playerId, cards: [...sugg.cards] });
      }
    });
  });

  let changed = true;
  let guard = 0;
  while (changed && guard < 60) {
    changed = false;
    guard++;

    constraints.forEach((c) => {
      const st = state[c.playerId];
      if (c.cards.some((cid) => st[cid] === "has")) return;
      const candidates = c.cards.filter((cid) => st[cid] !== "not");
      if (candidates.length === 1 && st[candidates[0]] !== "has") {
        setHas(c.playerId, candidates[0]);
        changed = true;
      }
    });

    players.forEach((p) => {
      const st = state[p.id];
      const hasCards = ALL_CARDS.filter((c) => st[c.id] === "has");
      hasCards.forEach((c) => {
        players.forEach((p2) => {
          if (p2.id !== p.id && state[p2.id][c.id] !== "not") { state[p2.id][c.id] = "not"; changed = true; }
        });
      });
      if (p.handSize != null && hasCards.length >= p.handSize) {
        ALL_CARDS.forEach((c) => { if (st[c.id] == null) { st[c.id] = "not"; changed = true; } });
      }
    });

    CATEGORIES.forEach((cat) => {
      const catIds = ALL_CARDS.filter((c) => c.cat === cat.key).map((c) => c.id);
      const unowned = catIds.filter((cid) => !players.some((p) => state[p.id][cid] === "has"));
      if (unowned.length === 1) {
        players.forEach((p) => { if (state[p.id][unowned[0]] !== "not") { state[p.id][unowned[0]] = "not"; changed = true; } });
      }
    });
  }

  const solution = {};
  CATEGORIES.forEach((cat) => {
    const catIds = ALL_CARDS.filter((c) => c.cat === cat.key).map((c) => c.id);
    const found = catIds.find((cid) => players.every((p) => state[p.id][cid] === "not"));
    solution[cat.key] = found || null;
  });

  const contradiction = constraints.some((c) => {
    const st = state[c.playerId];
    return !c.cards.some((cid) => st[cid] === "has") && c.cards.every((cid) => st[cid] === "not");
  });

  return { state, solution, contradiction };
}

function cardName(id) { const c = ALL_CARDS.find((c) => c.id === id); return c ? c.name : id; }
function cardCat(id) { const c = ALL_CARDS.find((c) => c.id === id); return c ? c.cat : null; }

// ---------------------------------------------------------------------------
export default function App() {
  const [game, setGame] = useState(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  });
  const [tab, setTab] = useState("board");

  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(game)); } catch (e) { /* best effort */ }
  }, [game]);

  const resetCase = () => {
    try { localStorage.removeItem(STORAGE_KEY); } catch (e) {}
    setGame(null);
    setTab("board");
  };

  if (!game) {
    return <Setup onComplete={(g) => { setGame(g); setTab("board"); }} />;
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-amber-50 via-orange-50 to-amber-100 pb-28 font-sans text-stone-800">
      <header className="bg-stone-950 text-amber-50 px-4 pt-6 pb-5 sticky top-0 z-20 shadow-lg rounded-b-3xl">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="p-2 rounded-full bg-amber-500/15 ring-1 ring-amber-500/30 shrink-0">
              <Flame size={19} className="text-amber-500" />
            </span>
            <div>
              <p className="text-[9px] uppercase tracking-[0.25em] text-amber-500 font-serif italic">Parker Brothers Style Detective Game</p>
              <h1 className="font-sans font-black text-2xl tracking-tight leading-none -mt-0.5">Clue Case File</h1>
            </div>
          </div>
          <button onClick={resetCase} className="p-2.5 rounded-full bg-stone-900 text-amber-500 shadow-inner" aria-label="Start a new case">
            <RotateCcw size={17} />
          </button>
        </div>
      </header>

      <main className="px-3 pt-5">
        {tab === "board" && <Board game={game} />}
        {tab === "lead" && <NewLead game={game} setGame={setGame} onSaved={() => setTab("log")} />}
        {tab === "log" && <Log game={game} setGame={setGame} />}
      </main>

      <nav className="fixed bottom-3 inset-x-3 bg-stone-950 text-amber-100 flex items-center justify-around rounded-full shadow-xl z-20 px-2 py-1.5 ring-1 ring-amber-500/20">
        <TabButton icon={<FileText size={17} />} label="Board" active={tab === "board"} onClick={() => setTab("board")} />
        <TabButton icon={<Search size={17} />} label="New Lead" active={tab === "lead"} onClick={() => setTab("lead")} />
        <TabButton icon={<ClipboardList size={17} />} label="Log" active={tab === "log"} onClick={() => setTab("log")} />
      </nav>
    </div>
  );
}

function TabButton({ icon, label, active, onClick }) {
  return (
    <button onClick={onClick} className={`flex-1 flex flex-col items-center gap-0.5 py-2 rounded-full text-[11px] ${active ? "bg-stone-800 text-amber-400" : "text-amber-100/50"}`}>
      {icon}
      {label}
    </button>
  );
}

// ---------------------------------------------------------------------------
// SETUP
// ---------------------------------------------------------------------------
function Setup({ onComplete }) {
  const [count, setCount] = useState(4);
  const [names, setNames] = useState(["Noah", "Chloe", "Mal", "Geo"]);
  const [meIndex, setMeIndex] = useState(3);
  const [handSizes, setHandSizes] = useState(defaultHandSizes(4));
  const [myCards, setMyCards] = useState([]);

  function defaultHandSizes(n) {
    const base = Math.floor(TOTAL_DEALT / n);
    const remainder = TOTAL_DEALT % n;
    return Array.from({ length: n }, (_, i) => base + (i < remainder ? 1 : 0));
  }

  const setCountAndResize = (n) => {
    n = Math.max(3, Math.min(6, n));
    setCount(n);
    setNames((prev) => Array.from({ length: n }, (_, i) => prev[i] || ""));
    setHandSizes(defaultHandSizes(n));
    if (meIndex >= n) setMeIndex(0);
  };

  const sum = handSizes.reduce((a, b) => a + (Number(b) || 0), 0);
  const handSizeOk = sum === TOTAL_DEALT;
  const namesOk = names.slice(0, count).every((n) => n.trim().length > 0);
  const cardsOk = myCards.length === Number(handSizes[meIndex] || 0);
  const canStart = handSizeOk && namesOk && cardsOk;

  const toggleCard = (id) => {
    setMyCards((prev) => (prev.includes(id) ? prev.filter((c) => c !== id) : prev.length < Number(handSizes[meIndex] || 0) ? [...prev, id] : prev));
  };

  const start = () => {
    const players = names.slice(0, count).map((name, i) => ({ id: uid(), name: name.trim(), isMe: i === meIndex, handSize: Number(handSizes[i]) }));
    onComplete({ players, myCards, suggestions: [] });
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-amber-50 via-orange-50 to-amber-100 font-sans text-stone-800 pb-10">
      <header className="bg-stone-950 text-amber-50 px-4 pt-7 pb-6 rounded-b-3xl shadow-lg">
        <div className="flex items-center gap-3">
          <span className="p-2.5 rounded-full bg-amber-500/15 ring-1 ring-amber-500/30 shrink-0">
            <Flame size={22} className="text-amber-500" />
          </span>
          <div>
            <p className="text-[9px] uppercase tracking-[0.25em] text-amber-500 font-serif italic">Parker Brothers Style Detective Game</p>
            <h1 className="font-sans font-black text-3xl tracking-tight leading-none -mt-0.5">Clue Case File</h1>
          </div>
        </div>
      </header>

      <div className="px-4 pt-6 space-y-6">
        <section>
          <SectionLabel>Players around the table</SectionLabel>
          <div className="flex items-center gap-3 mb-3">
            <button onClick={() => setCountAndResize(count - 1)} className="w-9 h-9 rounded-full bg-stone-950 text-amber-500 font-black text-lg shadow-sm">–</button>
            <span className="font-mono text-lg w-6 text-center">{count}</span>
            <button onClick={() => setCountAndResize(count + 1)} className="w-9 h-9 rounded-full bg-stone-950 text-amber-500 font-black text-lg shadow-sm">+</button>
            <span className="text-xs text-stone-500">players, in seating/turn order</span>
          </div>

          <div className="space-y-2">
            {Array.from({ length: count }).map((_, i) => (
              <div key={i} className="flex items-center gap-2 bg-white border border-amber-200 rounded-xl px-3 py-2 shadow-sm">
                <span className="text-xs font-mono text-stone-400 w-4">{i + 1}</span>
                <input
                  value={names[i] || ""}
                  onChange={(e) => setNames((prev) => { const n = [...prev]; n[i] = e.target.value; return n; })}
                  placeholder={`Player ${i + 1} name`}
                  className="flex-1 outline-none text-sm bg-transparent"
                />
                <label className="flex items-center gap-1 text-xs text-stone-600">
                  <input type="radio" name="me" checked={meIndex === i} onChange={() => { setMeIndex(i); setMyCards([]); }} />
                  Me
                </label>
              </div>
            ))}
          </div>
        </section>

        <section>
          <SectionLabel>Hand sizes</SectionLabel>
          <p className="text-xs text-stone-500 mb-2">18 cards get dealt (21 minus 3 in the case file). Adjust if your table dealt unevenly.</p>
          <div className="grid grid-cols-2 gap-2">
            {Array.from({ length: count }).map((_, i) => (
              <div key={i} className="flex items-center justify-between bg-white border border-amber-200 rounded-xl px-3 py-2 text-sm shadow-sm">
                <span className="truncate text-stone-600">{names[i] || `Player ${i + 1}`}</span>
                <input
                  type="number" min={0} max={TOTAL_DEALT}
                  value={handSizes[i]}
                  onChange={(e) => setHandSizes((prev) => { const n = [...prev]; n[i] = e.target.value; return n; })}
                  className="w-12 text-right font-mono bg-amber-50 border border-amber-200 rounded-lg px-1"
                />
              </div>
            ))}
          </div>
          <p className={`text-xs mt-1 ${handSizeOk ? "text-emerald-700" : "text-red-700"}`}>Total dealt: {sum} / {TOTAL_DEALT}</p>
        </section>

        <section>
          <SectionLabel>Your cards ({myCards.length}/{Number(handSizes[meIndex] || 0)})</SectionLabel>
          {CATEGORIES.map((cat) => (
            <div key={cat.key} className="mb-3">
              <p className="text-[11px] uppercase tracking-wide text-stone-500 mb-1.5 flex items-center gap-1"><cat.icon size={12} />{cat.label}</p>
              <div className="flex flex-wrap gap-1.5">
                {cat.cards.map((name) => {
                  const id = `${cat.key}|${name}`;
                  const sel = myCards.includes(id);
                  return (
                    <button
                      key={id} onClick={() => toggleCard(id)}
                      className={`text-xs px-3 py-1.5 rounded-full border flex items-center shadow-sm ${sel ? "bg-stone-950 text-amber-50 border-stone-950 ring-2 ring-amber-500/30" : "bg-white text-stone-600 border-amber-200"}`}
                    >{cat.key === "suspect" && <SuspectDot name={name} />}{name}</button>
                  );
                })}
              </div>
            </div>
          ))}
        </section>

        <button
          disabled={!canStart}
          onClick={start}
          className={`w-full py-3.5 rounded-xl font-black tracking-tight text-lg shadow-md ${canStart ? "bg-gradient-to-r from-red-700 to-red-800 text-white" : "bg-stone-200 text-stone-400 shadow-none"}`}
        >
          Open the Case
        </button>
        {!canStart && <p className="text-xs text-stone-500 text-center">Fill in every name, balance the hand-size total, and select your exact hand.</p>}
      </div>
    </div>
  );
}

function SectionLabel({ children }) {
  return <h2 className="font-serif text-sm uppercase tracking-[0.15em] text-stone-500 mb-2 border-b border-amber-300/60 pb-1">{children}</h2>;
}

// ---------------------------------------------------------------------------
// BOARD
// ---------------------------------------------------------------------------
function Board({ game }) {
  const { state, solution, contradiction } = useMemo(() => deduce(game), [game]);
  const players = game.players;

  return (
    <div className="space-y-4">
      {contradiction && (
        <div className="flex items-start gap-2 bg-red-50 border border-red-200 text-red-800 text-xs px-3 py-2.5 rounded-xl shadow-sm">
          <ShieldAlert size={16} className="shrink-0 mt-0.5" />
          Two entries in the log conflict with each other — a "yes" leaves someone with zero possible cards. Check the Log tab.
        </div>
      )}

      <div className="bg-white border border-amber-200 rounded-2xl overflow-hidden shadow-sm">
        <p className="bg-stone-950 text-amber-500 text-[11px] uppercase tracking-[0.15em] px-3.5 py-2">Verdict so far</p>
        <div className="divide-y divide-amber-100">
          {CATEGORIES.map((cat) => {
            const catIds = ALL_CARDS.filter((c) => c.cat === cat.key).map((c) => c.id);
            const remaining = catIds.filter((cid) => !players.some((p) => state[p.id][cid] === "has"));
            const solved = solution[cat.key];
            return (
              <div key={cat.key} className="px-3.5 py-2.5 flex items-center justify-between">
                <span className="text-xs uppercase tracking-wide text-stone-500 flex items-center gap-1"><cat.icon size={13} />{cat.label}</span>
                {solved ? (
                  <span className="inline-flex items-center gap-1.5 text-stone-800 font-black text-sm">
                    {cat.key === "suspect" && <SuspectDot name={cardName(solved)} />}
                    {cardName(solved)}
                    <span className="text-[9px] bg-gradient-to-r from-red-700 to-red-800 text-white rounded-full px-2 py-0.5 uppercase tracking-wide font-sans font-medium">Confirmed</span>
                  </span>
                ) : (
                  <details className="text-sm">
                    <summary className="cursor-pointer text-stone-600 list-none flex items-center gap-1">{remaining.length} possible <ChevronRight size={12} /></summary>
                    <div className="text-xs text-stone-500 mt-1 text-right">{remaining.map(cardName).join(", ")}</div>
                  </details>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="bg-white border border-amber-200 rounded-2xl overflow-x-auto shadow-sm">
        <table className="text-[10px] font-mono min-w-full">
          <thead>
            <tr>
              <th className="sticky left-0 bg-white text-left px-2 py-2 border-b border-amber-200 z-10">Card</th>
              {players.map((p) => (
                <th key={p.id} className="px-1 py-2 border-b border-amber-200 text-center font-sans font-medium text-[9px] whitespace-nowrap">
                  {p.name}{p.isMe ? <span className="text-red-700"> (me)</span> : ""}
                </th>
              ))}
              <th className="px-1 py-2 border-b border-amber-200 text-center font-sans font-medium text-[9px]">Case</th>
            </tr>
          </thead>
          <tbody>
            {CATEGORIES.map((cat) => (
              <React.Fragment key={cat.key}>
                <tr>
                  <td colSpan={players.length + 2} className="bg-stone-950 text-amber-500 text-[9px] uppercase tracking-[0.1em] px-2 py-1.5 sticky left-0">
                    <span className="inline-flex items-center gap-1"><cat.icon size={9} />{cat.label}</span>
                  </td>
                </tr>
                {cat.cards.map((name) => {
                  const id = `${cat.key}|${name}`;
                  return (
                    <tr key={id} className="odd:bg-amber-50/50">
                      <td className="sticky left-0 bg-inherit px-2 py-1.5 whitespace-nowrap border-r border-amber-100 flex items-center">
                        {cat.key === "suspect" && <SuspectDot name={name} small />}{name}
                      </td>
                      {players.map((p) => <td key={p.id} className="text-center px-1 py-1.5"><Cell v={state[p.id][id]} /></td>)}
                      <td className="text-center px-1 py-1.5">{solution[cat.key] === id ? <Check size={12} className="inline text-red-700" /> : <Circle size={5} className="inline text-stone-300" />}</td>
                    </tr>
                  );
                })}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-[10px] text-stone-500 px-1">✓ has the card · — ruled out · · still possible</p>
    </div>
  );
}

function Cell({ v }) {
  if (v === "has") return <Check size={12} className="inline text-red-700" />;
  if (v === "not") return <span className="text-stone-300">—</span>;
  return <span className="text-stone-300">·</span>;
}

// ---------------------------------------------------------------------------
// NEW LEAD (record a suggestion + responses, live as it happens)
// ---------------------------------------------------------------------------
function NewLead({ game, setGame, onSaved }) {
  const players = game.players;
  const [suggesterId, setSuggesterId] = useState(players[0].id);
  const [picks, setPicks] = useState({});
  const [responses, setResponses] = useState([]);
  const [resolved, setResolved] = useState(false);
  const [pendingMeChoice, setPendingMeChoice] = useState(null);

  const picksComplete = CATEGORIES.every((c) => picks[c.key]);
  const cardsChosen = picksComplete ? CATEGORIES.map((c) => picks[c.key]) : null;

  const order = useMemo(() => {
    const startIdx = players.findIndex((p) => p.id === suggesterId);
    const rest = [];
    for (let i = 1; i < players.length; i++) rest.push(players[(startIdx + i) % players.length]);
    return rest;
  }, [players, suggesterId]);

  const nextResponder = order[responses.length];

  useEffect(() => {
    if (!cardsChosen || resolved || !nextResponder || !nextResponder.isMe) { setPendingMeChoice(null); return; }
    const matches = cardsChosen.filter((cid) => game.myCards.includes(cid));
    if (matches.length === 0) {
      setResponses((r) => [...r, { playerId: nextResponder.id, result: "no" }]);
    } else if (matches.length === 1) {
      setResponses((r) => [...r, { playerId: nextResponder.id, result: "yes", shownCard: matches[0] }]);
      setResolved(true);
    } else {
      setPendingMeChoice(matches);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nextResponder, cardsChosen]);

  const addResponse = (result, shownCard) => {
    setResponses((r) => [...r, { playerId: nextResponder.id, result, shownCard }]);
    if (result === "yes") setResolved(true);
  };

  const undoLast = () => {
    setResponses((r) => r.slice(0, -1));
    setResolved(false);
    setPendingMeChoice(null);
  };

  const save = () => {
    const suggestion = { id: uid(), suggesterId, cards: cardsChosen, responses };
    setGame((g) => ({ ...g, suggestions: [...g.suggestions, suggestion] }));
    setPicks({}); setResponses([]); setResolved(false); setPendingMeChoice(null);
    onSaved();
  };

  const done = resolved || responses.length === order.length;

  return (
    <div className="space-y-4 pb-4">
      <section>
        <SectionLabel>Who suggested?</SectionLabel>
        <div className="grid grid-cols-2 gap-2">
          {players.map((p) => (
            <button key={p.id} onClick={() => { setSuggesterId(p.id); setResponses([]); setResolved(false); }}
              className={`text-base font-medium px-3 py-3.5 rounded-xl border shadow-sm ${suggesterId === p.id ? "bg-gradient-to-br from-stone-900 to-stone-950 text-amber-50 border-stone-950 ring-2 ring-amber-500/30" : "bg-white text-stone-600 border-amber-200"}`}>
              {p.name}{p.isMe ? " (me)" : ""}
            </button>
          ))}
        </div>
      </section>

      <section>
        <SectionLabel>The three cards named</SectionLabel>
        {CATEGORIES.map((cat) => (
          <div key={cat.key} className="mb-4">
            <p className="text-xs uppercase tracking-wide text-stone-500 mb-1.5 flex items-center gap-1"><cat.icon size={14} />{cat.label}</p>
            <div className="grid grid-cols-2 gap-2">
              {cat.cards.map((name) => {
                const id = `${cat.key}|${name}`;
                const sel = picks[cat.key] === id;
                return (
                  <button key={id} onClick={() => { setPicks((p) => ({ ...p, [cat.key]: id })); setResponses([]); setResolved(false); }}
                    className={`text-base font-medium px-3 py-3.5 rounded-xl border shadow-sm flex items-center ${sel ? "bg-gradient-to-br from-stone-900 to-stone-950 text-amber-50 border-stone-950 ring-2 ring-amber-500/30" : "bg-white text-stone-600 border-amber-200"}`}>
                    {cat.key === "suspect" && <SuspectDot name={name} />}{name}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </section>

      {picksComplete && (
        <section>
          <SectionLabel>Responses, in turn order</SectionLabel>
          <div className="space-y-1.5">
            {responses.map((r, i) => {
              const p = players.find((pp) => pp.id === r.playerId);
              return (
                <div key={i} className="flex items-center justify-between bg-white border border-amber-200 rounded-xl px-3.5 py-2.5 text-sm shadow-sm">
                  <span>{p.name}</span>
                  <span className={r.result === "yes" ? "text-red-700" : "text-stone-500"}>
                    {r.result === "yes" ? `Showed a card${r.shownCard ? ` — ${cardName(r.shownCard)}` : ""}` : "No"}
                  </span>
                </div>
              );
            })}

            {!done && nextResponder && !nextResponder.isMe && (
              <div className="bg-amber-100/70 border border-amber-200 rounded-xl px-3.5 py-3 shadow-sm">
                <p className="text-sm mb-2">{nextResponder.name}'s turn to answer:</p>
                <div className="flex gap-2">
                  <button onClick={() => addResponse("no")} className="flex-1 py-3 rounded-xl bg-stone-100 text-stone-700 text-base font-medium shadow-sm">No</button>
                  <button onClick={() => setPendingMeChoice("prompt")} className="flex-1 py-3 rounded-xl bg-gradient-to-r from-red-700 to-red-800 text-white text-base font-medium shadow-sm">Shows a card</button>
                </div>
                {pendingMeChoice === "prompt" && (
                  <div className="mt-3">
                    <p className="text-xs text-stone-500 mb-1.5">Which card did they show? (leave blank if unseen)</p>
                    <div className="grid grid-cols-2 gap-2">
                      {cardsChosen.map((cid) => (
                        <button key={cid} onClick={() => addResponse("yes", cid)} className="text-sm font-medium px-2 py-2.5 rounded-xl border bg-white border-amber-200 shadow-sm flex items-center">
                          {cardCat(cid) === "suspect" && <SuspectDot name={cardName(cid)} />}{cardName(cid)}
                        </button>
                      ))}
                      <button onClick={() => addResponse("yes")} className="text-sm font-medium px-2 py-2.5 rounded-xl border bg-white border-amber-200 shadow-sm text-stone-500 col-span-2">Unseen</button>
                    </div>
                  </div>
                )}
              </div>
            )}

            {!done && nextResponder && nextResponder.isMe && Array.isArray(pendingMeChoice) && (
              <div className="bg-amber-100/70 border border-amber-200 rounded-xl px-3.5 py-3 shadow-sm">
                <p className="text-sm mb-2">You must show one of these — which will you show?</p>
                <div className="grid grid-cols-2 gap-2">
                  {pendingMeChoice.map((cid) => (
                    <button key={cid} onClick={() => addResponse("yes", cid)} className="text-sm font-medium px-2 py-2.5 rounded-xl border bg-white border-amber-200 shadow-sm flex items-center">
                      {cardCat(cid) === "suspect" && <SuspectDot name={cardName(cid)} />}{cardName(cid)}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {responses.length > 0 && (
              <button onClick={undoLast} className="text-xs text-stone-500 underline px-1">Undo last response</button>
            )}
          </div>
        </section>
      )}

      {picksComplete && done && (
        <button onClick={save} className="w-full py-3.5 rounded-xl bg-gradient-to-r from-red-700 to-red-800 text-white font-black tracking-tight text-lg shadow-md">Log this lead</button>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// LOG
// ---------------------------------------------------------------------------
function Log({ game, setGame }) {
  const players = game.players;
  const remove = (id) => setGame((g) => ({ ...g, suggestions: g.suggestions.filter((s) => s.id !== id) }));

  if (game.suggestions.length === 0) {
    return <p className="text-sm text-stone-500 text-center mt-10">No leads logged yet. Head to "New Lead" after the first suggestion at the table.</p>;
  }

  return (
    <div className="space-y-2 pb-4">
      {game.suggestions.map((s, idx) => {
        const suggester = players.find((p) => p.id === s.suggesterId);
        return (
          <div key={s.id} className="bg-white border border-amber-200 rounded-xl px-3.5 py-2.5 shadow-sm">
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs text-stone-400">Lead #{idx + 1}</span>
              <button onClick={() => remove(s.id)} className="text-stone-400 p-1 rounded-full"><Trash2 size={14} /></button>
            </div>
            <p className="text-sm mb-1 flex flex-wrap items-center gap-1">
              <span className="font-medium">{suggester?.name}</span> suggested
              {s.cards.map((cid) => (
                <span key={cid} className="font-mono text-xs inline-flex items-center">
                  {cardCat(cid) === "suspect" && <SuspectDot name={cardName(cid)} />}{cardName(cid)}
                </span>
              ))}
            </p>
            <div className="text-xs text-stone-500 space-y-0.5">
              {s.responses.map((r, i) => {
                const p = players.find((pp) => pp.id === r.playerId);
                return <p key={i}>{p?.name}: {r.result === "yes" ? `showed a card${r.shownCard ? ` (${cardName(r.shownCard)})` : ""}` : "no"}</p>;
              })}
              {s.responses.length === 0 && <p>No one responded (not fully logged)</p>}
            </div>
          </div>
        );
      })}
    </div>
  );
}
