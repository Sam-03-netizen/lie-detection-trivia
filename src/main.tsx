import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { AnimatePresence, motion } from 'framer-motion';
import { ArrowRight, Check, Copy, Crown, Eye, LogOut, Play, RefreshCw, Sparkles, Trophy, Users, X } from 'lucide-react';
import { supabase } from './supabase';
import type { Answer, Player, Room, RoomStatus } from './types';
import './styles.css';

type View = { room:Room; round:any; question:any; answers:Answer[]; my_answer_submitted?:boolean; my_vote_submitted?:boolean; results?:any[] };
type Screen = 'home'|'lobby'|'game';

const COLORS = ['violet','cyan','pink','amber','emerald','blue','rose','indigo'];

function App(){
  const [screen,setScreen]=useState<Screen>('home');
  const [mode,setMode]=useState<'create'|'join'|null>(null);
  const [name,setName]=useState('');
  const [code,setCode]=useState('');
  const [room,setRoom]=useState<Room|null>(null);
  const [me,setMe]=useState<Player|null>(null);
  const [players,setPlayers]=useState<Player[]>([]);
  const [view,setView]=useState<View|null>(null);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const [notice,setNotice]=useState('');
  const [selected,setSelected]=useState<string|null>(null);
  const [fake,setFake]=useState('');
  const [copied,setCopied]=useState(false);
  const [answerLocked,setAnswerLocked]=useState(false);
  const [voteLocked,setVoteLocked]=useState(false);
  const [ready,setReady]=useState(false);

  const refresh = async (roomId:string) => {
    const {data,error}=await supabase.rpc('get_round_view',{p_room_id:roomId});
    if(error){setError(error.message);return;}
    const v=data as View;
    setRoom(v.room); setView(v);
    setAnswerLocked(Boolean(v.my_answer_submitted));
    setVoteLocked(Boolean(v.my_vote_submitted));
    if(v.room.status==='lobby') { setAnswerLocked(false); setVoteLocked(false); }
    const {data:ps}=await supabase.from('players').select('*').eq('room_id',roomId).order('joined_at');
    if(ps) setPlayers(ps as Player[]);
    if(v.room.status==='lobby') setScreen('lobby'); else setScreen('game');
  };

  useEffect(()=>{
    (async()=>{
      const {data}=await supabase.auth.getSession();
      if(!data.session){
        const r=await supabase.auth.signInAnonymously();
        if(r.error){setError('Realtime backend is not configured yet. Enable Anonymous Sign-ins in Supabase.');return;}
      }
      setReady(true);
      const saved=localStorage.getItem('ldt_session');
      if(saved){
        try{
          const s=JSON.parse(saved); setName(s.name||'');
          const rr=await supabase.rpc('reconnect_player',{p_room_id:s.roomId});
          if(!rr.error){setMe(rr.data.player); await refresh(s.roomId);}
        }catch{}
      }
    })();
  },[]);

  useEffect(()=>{
    if(!room) return;
    const channel=supabase.channel(`room-${room.id}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'rooms',filter:`id=eq.${room.id}`},()=>refresh(room.id))
      .on('postgres_changes',{event:'*',schema:'public',table:'players',filter:`room_id=eq.${room.id}`},()=>refresh(room.id))
      .subscribe();
    return()=>{supabase.removeChannel(channel);};
  },[room?.id]);

  useEffect(()=>{
    if(!me||!room) return;
    const id = window.setInterval(
      () => supabase.rpc('heartbeat', { p_room_id: room.id }),
      10000
    );
    const watchdog=window.setInterval(()=>{ if(me.id===room.host_player_id && (room.status==='answering'||room.status==='voting')) supabase.rpc('advance_inactive',{p_room_id:room.id}); },10000);
    return()=>{window.clearInterval(id);window.clearInterval(watchdog);};
  },[me?.id,room?.id]);

  const doCreate=async()=>{
    if(!name.trim()) return setError('Enter your name first.');
    setBusy(true);setError('');
    const {data,error}=await supabase.rpc('create_room',{p_name:name.trim()});
    setBusy(false);
    if(error) return setError(error.message);
    setMe(data.player); setRoom(data.room); localStorage.setItem('ldt_session',JSON.stringify({roomId:data.room.id,name:data.player.name}));
    await refresh(data.room.id);
  };
  const doJoin=async()=>{
    if(!name.trim()||code.trim().length!==4) return setError('Enter your name and a 4-character room code.');
    setBusy(true);setError('');
    const {data,error}=await supabase.rpc('join_room',{p_code:code.trim().toUpperCase(),p_name:name.trim()});
    setBusy(false);
    if(error) return setError(error.message);
    setMe(data.player); setRoom(data.room); localStorage.setItem('ldt_session',JSON.stringify({roomId:data.room.id,name:data.player.name}));
    await refresh(data.room.id);
  };
  const start=async()=>{
    if(!room) return;
    setBusy(true);setError(''); const {error}=await supabase.rpc('start_game',{p_room_id:room.id}); setBusy(false); if(error)setError(error.message);
  };
  const submitFake=async()=>{
    if(!room||!fake.trim()) return;
    setBusy(true);setError(''); const {error}=await supabase.rpc('submit_answer',{p_room_id:room.id,p_text:fake.trim()}); setBusy(false); if(error)setError(error.message); else {setFake('');setAnswerLocked(true);setNotice('Your bluff is locked in.');}
  };
  const submitVote=async()=>{
    if(!room||!selected)return;
    setBusy(true);setError(''); const {error}=await supabase.rpc('submit_vote',{p_room_id:room.id,p_answer_id:selected}); setBusy(false); if(error)setError(error.message); else {setVoteLocked(true);setNotice('Vote locked.');}
  };
  const reveal=async()=>{if(!room)return;setBusy(true);const {error}=await supabase.rpc('finish_reveal',{p_room_id:room.id});setBusy(false);if(error)setError(error.message);};
  const next=async()=>{if(!room)return;setBusy(true);const {error}=await supabase.rpc('next_round',{p_room_id:room.id});setBusy(false);if(error)setError(error.message);setSelected(null);};
  const playAgain=async()=>{if(!room)return;setBusy(true);const {error}=await supabase.rpc('play_again',{p_room_id:room.id});setBusy(false);if(error)setError(error.message);setSelected(null);};
  const leave=async()=>{if(room) await supabase.rpc('leave_room',{p_room_id:room.id});localStorage.removeItem('ldt_session');setRoom(null);setMe(null);setView(null);setPlayers([]);setScreen('home');setMode(null);};
  const copy=async()=>{if(!room)return;navigator.clipboard?.writeText(room.code);setCopied(true);setTimeout(()=>setCopied(false),1200);};

  if(!ready) return <Loading message="Waking up the game table…"/>;
  return <div className="app-shell">
    <div className="ambient ambient-a"/><div className="ambient ambient-b"/>
    <header className="topbar"><div className="brand"><div className="brand-mark"><Eye size={20}/></div><span>Lie-Detection Trivia</span></div>{room&&<button className="ghost-button" onClick={leave}><LogOut size={16}/> Leave</button>}</header>
    <main className="main">
      {error&&<div className="toast error"><X size={16}/>{error}<button onClick={()=>setError('')}>×</button></div>}
      {notice&&<div className="toast success"><Check size={16}/>{notice}<button onClick={()=>setNotice('')}>×</button></div>}
      <AnimatePresence mode="wait">
        {screen==='home'&&<Home mode={mode} setMode={setMode} name={name} setName={setName} code={code} setCode={setCode} busy={busy} onCreate={doCreate} onJoin={doJoin}/>} 
        {screen==='lobby'&&room&&<Lobby room={room} players={players} me={me} busy={busy} onStart={start} onCopy={copy} copied={copied}/>} 
        {screen==='game'&&room&&view&&me&&<Game room={room} view={view} players={players} me={me} busy={busy} answerLocked={answerLocked} voteLocked={voteLocked} fake={fake} setFake={setFake} selected={selected} setSelected={setSelected} onFake={submitFake} onVote={submitVote} onReveal={reveal} onNext={next} onPlayAgain={playAgain}/>} 
      </AnimatePresence>
    </main>
    <footer>3 rounds · bluff boldly · trust nobody</footer>
  </div>
}

function Home(p:any){
 return <motion.section className="home" initial={{opacity:0,y:12}} animate={{opacity:1,y:0}} exit={{opacity:0,y:-12}}>
   <div className="hero-badge"><Sparkles size={15}/> A social bluffing game</div>
   <h1>Can you spot<br/><span>the lie?</span></h1>
   <p className="hero-copy">One strange fact. Everyone invents a believable answer. Then you decide what’s true.</p>
   <div className="home-card">
    {!p.mode?<><button className="primary big" onClick={()=>p.setMode('create')}><Play size={19}/> Create a game</button><button className="secondary big" onClick={()=>p.setMode('join')}><Users size={19}/> Join a game</button><div className="rules"><b>How it works</b><span>① Make a bluff</span><span>② Vote for the truth</span><span>③ Score points for knowledge & deception</span></div></>:<>
      <button className="back-link" onClick={()=>p.setMode(null)}>← Back</button><h2>{p.mode==='create'?'Create your game':'Join a game'}</h2>
      <label>Your name<input autoFocus maxLength={24} value={p.name} onChange={e=>p.setName(e.target.value)} placeholder="e.g. Samriddhi"/></label>
      {p.mode==='join'&&<label>Room code<input maxLength={4} className="code-input" value={p.code} onChange={e=>p.setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g,''))} placeholder="ABCD"/></label>}
      <button className="primary big" disabled={p.busy} onClick={p.mode==='create'?p.onCreate:p.onJoin}>{p.busy?'Connecting…':p.mode==='create'?'Create room':'Join room'}<ArrowRight size={19}/></button>
    </>}
   </div>
 </motion.section>
}

function Lobby({room,players,me,busy,onStart,onCopy,copied}:any){
 return <motion.section className="panel" initial={{opacity:0,scale:.98}} animate={{opacity:1,scale:1}}>
  <div className="room-head"><div><div className="eyebrow">Game lobby</div><h2>Waiting for your crew</h2></div><div className="room-code" onClick={onCopy}><small>ROOM CODE</small><strong>{room.code}</strong>{copied?<Check size={15}/>:<Copy size={15}/>}</div></div>
  <div className="share-line">Share the code with your friends. You need at least 2 players to start.</div>
  <div className="player-grid">{players.map((pl:Player,i:number)=><div className="player-chip" key={pl.id}><div className={`avatar ${COLORS[i%COLORS.length]}`}>{pl.name[0]?.toUpperCase()}</div><div><b>{pl.name}</b>{pl.id===room.host_player_id&&<small>HOST</small>}</div>{pl.id===me.id&&<span className="you">YOU</span>}</div>)}</div>
  <div className="lobby-actions"> <span><Users size={16}/> {players.length} player{players.length!==1?'s':''}</span>{me.id===room.host_player_id?<button className="primary" disabled={busy||players.length<2} onClick={onStart}>{players.length<2?'Waiting for 2+ players':'Start game'}<ArrowRight size={18}/></button>:<div className="waiting"><span className="pulse"/> Waiting for the host to start…</div>}</div>
 </motion.section>
}

function Game({room,view,players,me,busy,answerLocked,voteLocked,fake,setFake,selected,setSelected,onFake,onVote,onReveal,onNext,onPlayAgain}:any){
 const status:RoomStatus=room.status;
 const answered=answerLocked; // vote visibility is intentionally private; local state is enough for this session.
 const activePlayers=players.filter((p:Player)=>p.connected);
 return <motion.section className="game-wrap" initial={{opacity:0,y:12}} animate={{opacity:1,y:0}}>
   <div className="game-meta"><span className="round-pill">ROUND {room.current_round} / 3</span><div className="score-strip">{players.slice().sort((a:Player,b:Player)=>b.score-a.score).slice(0,4).map((p:Player)=><span key={p.id} className={p.id===me.id?'mine':''}>{p.name} <b>{p.score}</b></span>)}</div></div>
   {status==='answering'&&<AnswerPhase question={view.question} fake={fake} setFake={setFake} submitted={answered} onSubmit={onFake}/>} 
  {status==='voting'&&<VotePhase question={view.question} answers={view.answers||[]} selected={selected} setSelected={setSelected} onVote={onVote} busy={busy} voteLocked={voteLocked}/>} 
   {status==='reveal'&&<RevealPhase question={view.question} answers={view.answers||[]} players={players} me={me} room={room} onReveal={onReveal} busy={busy}/>} 
   {status==='leaderboard'&&<Leaderboard players={players} me={me} room={room} round={room.current_round} results={view.results||[]} onNext={onNext} busy={busy}/>} 
   {status==='finished'&&<Final players={players} me={me} room={room} onPlayAgain={onPlayAgain} busy={busy}/>} 
   <div className="tip">{status==='answering'?'Make your lie believable enough to fool someone.':status==='voting'?'One answer is true. The others were written by players.':'The table is synced in real time.'}</div>
 </motion.section>
}

function AnswerPhase({question,fake,setFake,submitted,onSubmit}:any){return <div className="stage-card"><div className="stage-icon">🤫</div><div className="eyebrow">Everybody writes a lie</div><h2>{question.question}</h2>{submitted?<div className="locked"><Check size={22}/><div><b>Bluff locked in</b><span>Waiting for the other players…</span></div></div>:<><label className="answer-box"><span>Your believable fake answer</span><input maxLength={120} autoFocus value={fake} onChange={e=>setFake(e.target.value)} onKeyDown={e=>{if(e.key==='Enter')onSubmit()}} placeholder="Make it sound real…"/></label><button className="primary wide" disabled={!fake.trim()} onClick={onSubmit}>Lock in my bluff <ArrowRight size={18}/></button></>}</div>}

function VotePhase({
  question,
  answers,
  selected,
  setSelected,
  onVote,
  busy,
  voteLocked
}: any) {

  return (
    <div className="stage-card">

      <div className="stage-icon">🕵️</div>

      <div className="eyebrow">
        Now find the truth
      </div>

      <h2>{question.question}</h2>

      <p className="context">
        Pick the answer you believe is real.
      </p>

      <div className="answer-list">

        {answers.map((a: Answer, i: number) => (
            <button
              key={a.id}
              className={`answer-option
                ${selected === a.id ? 'selected' : ''}
                ${a.is_mine ? 'disabled' : ''}
              `}
              disabled={a.is_mine || voteLocked}
              onClick={() => setSelected(a.id)}
            >

              <span className="option-letter">
                {String.fromCharCode(65 + i)}
              </span>

              <span>{a.answer_text}</span>

              {a.is_mine ? (
                <small>Your bluff</small>
              ) : selected === a.id ? (
                <Check size={19} />
              ) : null}

            </button>
        ))}

      </div>

      <button
        className="primary wide"
        disabled={!selected || busy || voteLocked}
        onClick={onVote}
      >
        {voteLocked ? 'Vote locked' : 'Lock my vote'}
        <Check size={18} />
      </button>

    </div>
  );
}

function RevealPhase({question,answers,players,me,room,onReveal,busy}:any){const truth=answers.find((a:Answer)=>a.is_real);return <div className="stage-card reveal-card"><div className="stage-icon">🎯</div><div className="eyebrow">The truth is out</div><h2>The real answer was…</h2><div className="truth">{truth?.answer_text||question.correct_answer}</div><p className="context">{question.context}</p><div className="reveal-list">{answers.map((a:Answer)=><div className={`reveal-row ${a.is_real?'real':''}`} key={a.id}><span>{a.answer_text}</span><small>{a.is_real?'REAL ANSWER':players.find((p:Player)=>p.id===a.player_id)?.name||'Unknown bluff'}</small></div>)}</div>{me.id===room.host_player_id&&<div className="reveal-action"><button className="primary wide" disabled={busy} onClick={onReveal}>Reveal scores <ArrowRight size={18}/></button></div>}{me.id!==room.host_player_id&&<div className="waiting"><span className="pulse"/> Waiting for the host to reveal scores…</div>}</div>}

function Leaderboard({players,me,room,round,results,onNext,busy}:any){const sorted=players.slice().sort((a:Player,b:Player)=>b.score-a.score);return <div className="stage-card"><div className="stage-icon">🏆</div><div className="eyebrow">Round {round} complete</div><h2>Leaderboard</h2><div className="leaderboard">{sorted.map((p:Player,i:number)=><div className={`leader-row ${p.id===me.id?'mine':''}`} key={p.id}><strong>#{i+1}</strong><div className={`avatar tiny ${COLORS[i%COLORS.length]}`}>{p.name[0]}</div><span>{p.name}{p.id===me.id&&<small> YOU</small>}</span><b>{p.score}</b></div>)}</div>{results?.length>0&&<div className="round-results">{results.slice().sort((a:any,b:any)=>b.score_delta-a.score_delta).map((r:any)=><div key={r.player_id}><span>{players.find((p:Player)=>p.id===r.player_id)?.name}</span><small>{r.truth_found?'Truth +100 · ':''}{r.fooled?`Fooled ${r.fooled} · +${r.fooled*50}`:'No bluff points'}</small><b>+{r.score_delta}</b></div>)}</div>}{me.id===room.host_player_id?<button className="primary wide" disabled={busy} onClick={onNext}>{round===3?'See final winner':'Next round'}<ArrowRight size={18}/></button>:<div className="waiting"><span className="pulse"/> Waiting for the host…</div>}</div>}

function Final({players,me,room,onPlayAgain,busy}:any){const sorted=players.slice().sort((a:Player,b:Player)=>b.score-a.score);const winner=sorted[0];const isHost=me.id===room.host_player_id;return <div className="stage-card final-card"><div className="stage-icon"><Trophy size={34}/></div><div className="eyebrow">Three rounds. One winner.</div><h2>{winner?.id===me.id?'You won!':'Game over!'}</h2><div className="winner-name"><Crown size={23}/>{winner?.name}</div><div className="leaderboard">{sorted.map((p:Player,i:number)=><div className={`leader-row ${p.id===me.id?'mine':''}`} key={p.id}><strong>{['🥇','🥈','🥉'][i]||`#${i+1}`}</strong><span>{p.name}</span><b>{p.score}</b></div>)}</div>{isHost?<button className="primary wide" disabled={busy} onClick={onPlayAgain}>Play again <RefreshCw size={18}/></button>:<div className="waiting"><span className="pulse"/> Waiting for host…</div>}</div>}

function Loading({message}:{message:string}){return <div className="loading"><div className="brand-mark"><Eye size={22}/></div><span>{message}</span></div>}

createRoot(document.getElementById('root')!).render(<App/>);
