-- Lie-Detection Trivia MVP schema + authoritative RPCs
create extension if not exists pgcrypto;

drop table if exists public.votes cascade;
drop table if exists public.answers cascade;
drop table if exists public.rounds cascade;
drop table if exists public.players cascade;
drop table if exists public.rooms cascade;
drop table if exists public.questions cascade;

do $$ begin create type room_status as enum ('lobby','answering','voting','reveal','leaderboard','finished'); exception when duplicate_object then null; end $$;

create table public.questions (
  id bigint primary key,
  question text not null,
  correct_answer text not null,
  context text not null
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  host_player_id uuid,
  status room_status not null default 'lobby',
  current_round integer not null default 0,
  updated_at timestamptz not null default now()
);

create table public.players (
  id uuid primary key references auth.users(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 24),
  score integer not null default 0,
  connected boolean not null default true,
  last_seen timestamptz not null default now(),
  joined_at timestamptz not null default now()
);

alter table public.rooms add constraint rooms_host_fk foreign key (host_player_id) references public.players(id) on delete set null;

create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  round_number integer not null check (round_number between 1 and 3),
  question_id bigint not null references public.questions(id),
  status room_status not null,
  results jsonb not null default '[]'::jsonb,
  unique(room_id, round_number)
);

create table public.answers (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,
  answer_text text not null check (char_length(answer_text) between 1 and 120),
  is_real boolean not null default false,
  unique(round_id, player_id)
);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  answer_id uuid not null references public.answers(id) on delete cascade,
  unique(round_id, player_id)
);

create index players_room_idx on public.players(room_id);
create index rounds_room_idx on public.rounds(room_id);
create index answers_round_idx on public.answers(round_id);
create index votes_round_idx on public.votes(round_id);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.questions enable row level security;
alter table public.rounds enable row level security;
alter table public.answers enable row level security;
alter table public.votes enable row level security;

-- Public reads needed by the realtime client. Mutations are performed only through RPCs.
create policy rooms_select on public.rooms for select using (true);
create policy players_select on public.players for select using (true);
-- Questions are only exposed through get_round_view; correct answers stay server-side.
create policy rounds_select on public.rounds for select using (true);
-- Answers and votes are read only through get_round_view so the real answer cannot leak.


-- Prevent direct client writes.
create policy no_direct_room_insert on public.rooms for insert with check (false);
create policy no_direct_room_update on public.rooms for update using (false);
create policy no_direct_room_delete on public.rooms for delete using (false);
create policy no_direct_player_insert on public.players for insert with check (false);
create policy no_direct_player_update on public.players for update using (false);
create policy no_direct_player_delete on public.players for delete using (false);
create policy no_direct_answer_insert on public.answers for insert with check (false);
create policy no_direct_answer_update on public.answers for update using (false);
create policy no_direct_vote_insert on public.votes for insert with check (false);
create policy no_direct_vote_update on public.votes for update using (false);

create or replace function public.make_code() returns text language plpgsql as $$
declare c text;
begin
  loop
    c := upper(substr(encode(gen_random_bytes(4),'hex'),1,4));
    exit when not exists(select 1 from public.rooms where code=c);
  end loop;
  return c;
end $$;

create or replace function public.create_room(p_name text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; p public.players;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if char_length(trim(p_name)) < 1 or char_length(trim(p_name)) > 24 then raise exception 'Name must be 1-24 characters'; end if;
  insert into rooms(code,status,current_round) values(make_code(),'lobby',0) returning * into r;
  insert into players(id,room_id,name,last_seen) values(auth.uid(),r.id,trim(p_name),now()) returning * into p;
  update rooms set host_player_id=p.id where id=r.id returning * into r;
  return jsonb_build_object('room',to_jsonb(r),'player',to_jsonb(p));
end $$;

create or replace function public.join_room(p_code text,p_name text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; p public.players; existing public.players;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into r from rooms where code=upper(trim(p_code));
  if r.id is null then raise exception 'Room not found'; end if;
  if r.status <> 'lobby' then raise exception 'Game already started'; end if;
  if char_length(trim(p_name)) < 1 or char_length(trim(p_name)) > 24 then raise exception 'Name must be 1-24 characters'; end if;
  select * into existing from players where id=auth.uid();
  if existing.id is not null and existing.room_id=r.id then
    update players set name=trim(p_name), connected=true, last_seen=now() where id=auth.uid() returning * into p;
  else
    if (select count(*) from players where room_id=r.id and connected) >= 12 then raise exception 'Room is full'; end if;
    if existing.id is not null then delete from players where id=auth.uid(); end if;
    insert into players(id,room_id,name,last_seen) values(auth.uid(),r.id,trim(p_name),now()) returning * into p;
  end if;
  return jsonb_build_object('room',to_jsonb(r),'player',to_jsonb(p));
end $$;

create or replace function public.reconnect_player(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare p public.players; r public.rooms;
begin
  select * into p from players where id=auth.uid() and room_id=p_room_id;
  if p.id is null then raise exception 'Player session not found'; end if;
  update players set connected=true,last_seen=now() where id=auth.uid() returning * into p;
  select * into r from rooms where id=p_room_id;
  return jsonb_build_object('room',to_jsonb(r),'player',to_jsonb(p));
end $$;

create or replace function public.heartbeat(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  update players set connected=true,last_seen=now() where id=auth.uid() and room_id=p_room_id;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.advance_inactive(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; rd public.rounds; waiting integer; new_host uuid;
begin
  select * into r from rooms where id=p_room_id for update;
  if not exists(select 1 from players where id=auth.uid() and room_id=r.id) then raise exception 'Not a player in this room'; end if;
  update players set connected=false where room_id=r.id and connected=true and last_seen < now()-interval '60 seconds';
  if not exists(select 1 from players where id=r.host_player_id and connected=true and last_seen > now()-interval '60 seconds') then
    select id into new_host from players where room_id=r.id and connected=true and last_seen > now()-interval '60 seconds' order by joined_at limit 1;
    if new_host is not null then update rooms set host_player_id=new_host,updated_at=now() where id=r.id returning * into r; end if;
  end if;
  if r.status='answering' then
    select * into rd from rounds where room_id=r.id and round_number=r.current_round;
    select count(*) into waiting from players where room_id=r.id and connected and last_seen > now()-interval '60 seconds' and not exists(select 1 from answers a where a.round_id=rd.id and a.player_id=players.id);
    if waiting=0 then update rounds set status='voting' where id=rd.id; update rooms set status='voting',updated_at=now() where id=r.id returning * into r; end if;
  elsif r.status='voting' then
    select * into rd from rounds where room_id=r.id and round_number=r.current_round;
    select count(*) into waiting from players where room_id=r.id and connected and last_seen > now()-interval '60 seconds' and not exists(select 1 from votes v where v.round_id=rd.id and v.player_id=players.id);
    if waiting=0 then update rounds set status='reveal' where id=rd.id; update rooms set status='reveal',updated_at=now() where id=r.id returning * into r; end if;
  end if;
  return jsonb_build_object('room',to_jsonb(r));
end $$;

create or replace function public.start_game(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; q public.questions; rd public.rounds;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.host_player_id <> auth.uid() then raise exception 'Only the host can start'; end if;
  if r.status <> 'lobby' then raise exception 'Game has already started'; end if;
  if (select count(*) from players where room_id=r.id and connected and last_seen > now()-interval '40 seconds') < 2 then raise exception 'At least 2 players are required'; end if;
  select * into q from questions order by random() limit 1;
  insert into rounds(room_id,round_number,question_id,status) values(r.id,1,q.id,'answering') returning * into rd;
  insert into answers(round_id,player_id,answer_text,is_real) values(rd.id,null,q.correct_answer,true);
  update rooms set current_round=1,status='answering',updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd));
end $$;

create or replace function public.submit_answer(p_room_id uuid,p_text text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; rd public.rounds; q public.questions; n integer;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.status <> 'answering' then raise exception 'Not accepting answers'; end if;
  select * into rd from rounds where room_id=r.id and round_number=r.current_round;
  select * into q from questions where id=rd.question_id;
  if not exists(select 1 from players where id=auth.uid() and room_id=r.id and connected) then raise exception 'Not a connected player'; end if;
  if exists(select 1 from answers where round_id=rd.id and player_id=auth.uid()) then raise exception 'Answer already submitted'; end if;
  if lower(trim(p_text))=lower(trim(q.correct_answer)) then raise exception 'Your fake answer cannot be the real answer'; end if;
  insert into answers(round_id,player_id,answer_text) values(rd.id,auth.uid(),trim(p_text));
  select count(*) into n from players where room_id=r.id and connected and last_seen > now()-interval '60 seconds' and not exists(select 1 from answers a where a.round_id=rd.id and a.player_id=players.id);
  if n=0 then
    update rounds set status='voting' where id=rd.id;
    update rooms set status='voting',updated_at=now() where id=r.id;
  end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.submit_vote(p_room_id uuid,p_answer_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; rd public.rounds; n integer;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.status <> 'voting' then raise exception 'Not accepting votes'; end if;
  select * into rd from rounds where room_id=r.id and round_number=r.current_round;
  if not exists(select 1 from players where id=auth.uid() and room_id=r.id and connected) then raise exception 'Not a connected player'; end if;
  if exists(select 1 from votes where round_id=rd.id and player_id=auth.uid()) then raise exception 'Vote already submitted'; end if;
  if not exists(select 1 from answers where id=p_answer_id and round_id=rd.id) then raise exception 'Invalid answer'; end if;
  if exists(select 1 from answers where id=p_answer_id and player_id=auth.uid()) then raise exception 'You cannot vote for your own answer'; end if;
  insert into votes(round_id,player_id,answer_id) values(rd.id,auth.uid(),p_answer_id);
  select count(*) into n from players where room_id=r.id and connected and last_seen > now()-interval '60 seconds' and not exists(select 1 from votes v where v.round_id=rd.id and v.player_id=players.id);
  if n=0 then
    update rounds set status='reveal' where id=rd.id;
    update rooms set status='reveal',updated_at=now() where id=r.id;
  end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.get_round_view(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; rd public.rounds; q public.questions; result jsonb;
begin
  select * into r from rooms where id=p_room_id;
  if r.id is null then raise exception 'Room not found'; end if;
  select * into rd from rounds where room_id=r.id and round_number=r.current_round;
  if rd.id is null then return jsonb_build_object('room',to_jsonb(r),'round',null,'question',null,'answers','[]'::jsonb,'reveal',null); end if;
  select * into q from questions where id=rd.question_id;
  if r.status='answering' then
    return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd),'question',jsonb_build_object('id',q.id,'question',q.question,'context',q.context),'answers','[]'::jsonb,'my_answer_submitted',exists(select 1 from answers a where a.round_id=rd.id and a.player_id=auth.uid()),'my_vote_submitted',false);
  elsif r.status='voting' then
    return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd),'question',jsonb_build_object('id',q.id,'question',q.question,'context',q.context),'answers',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'answer_text',a.answer_text,'is_mine',coalesce(a.player_id=auth.uid(),false)) order by random()) from answers a where a.round_id=rd.id),'[]'::jsonb),'my_answer_submitted',exists(select 1 from answers a where a.round_id=rd.id and a.player_id=auth.uid() and not a.is_real),'my_vote_submitted',exists(select 1 from votes v where v.round_id=rd.id and v.player_id=auth.uid()),'results',rd.results);
  end if;
  return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd),'question',to_jsonb(q),'answers',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'player_id',a.player_id,'answer_text',a.answer_text,'is_real',a.is_real) order by a.id) from answers a where a.round_id=rd.id),'[]'::jsonb),'my_answer_submitted',exists(select 1 from answers a where a.round_id=rd.id and a.player_id=auth.uid() and not a.is_real),'my_vote_submitted',exists(select 1 from votes v where v.round_id=rd.id and v.player_id=auth.uid()),'results',rd.results);
end $$;

create or replace function public.finish_reveal(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; rd public.rounds; p record; delta integer; fooled integer; found boolean; results jsonb:='[]'::jsonb;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.host_player_id <> auth.uid() then raise exception 'Only the host can continue'; end if;
  if r.status <> 'reveal' then raise exception 'Not in reveal'; end if;
  select * into rd from rounds where room_id=r.id and round_number=r.current_round;
  for p in select * from players where room_id=r.id loop
    found := exists(select 1 from votes v join answers a on a.id=v.answer_id where v.round_id=rd.id and v.player_id=p.id and a.is_real);
    fooled := coalesce((select count(*) from votes v join answers a on a.id=v.answer_id where v.round_id=rd.id and a.player_id=p.id and not a.is_real),0);
    delta := (case when found then 100 else 0 end) + fooled*50;
    update players set score=score+delta where id=p.id;
    results := results || jsonb_build_array(jsonb_build_object('player_id',p.id,'score_delta',delta,'truth_found',found,'fooled',fooled));
  end loop;
  update rounds set status='leaderboard',results=results where id=rd.id;
  update rooms set status='leaderboard',updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('room',to_jsonb(r),'results',results);
end $$;

create or replace function public.next_round(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; q public.questions; rd public.rounds; prev_q bigint;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.host_player_id <> auth.uid() then raise exception 'Only the host can continue'; end if;
  if r.status <> 'leaderboard' then raise exception 'Not ready for next round'; end if;
  if r.current_round >= 3 then
    update rooms set status='finished',updated_at=now() where id=r.id returning * into r;
    return jsonb_build_object('room',to_jsonb(r));
  end if;
  select question_id into prev_q from rounds where room_id=r.id order by round_number desc limit 1;
  select * into q from questions where id<>prev_q order by random() limit 1;
  insert into rounds(room_id,round_number,question_id,status) values(r.id,r.current_round+1,q.id,'answering') returning * into rd;
  insert into answers(round_id,player_id,answer_text,is_real) values(rd.id,null,q.correct_answer,true);
  update rooms set current_round=r.current_round+1,status='answering',updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd));
end $$;

create or replace function public.play_again(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; q public.questions; rd public.rounds;
begin
  select * into r from rooms where id=p_room_id for update;
  if r.host_player_id <> auth.uid() then raise exception 'Only the host can restart'; end if;
  delete from votes where round_id in(select id from rounds where room_id=r.id);
  delete from answers where round_id in(select id from rounds where room_id=r.id);
  delete from rounds where room_id=r.id;
  update players set score=0,connected=true where room_id=r.id;
  select * into q from questions order by random() limit 1;
  insert into rounds(room_id,round_number,question_id,status) values(r.id,1,q.id,'answering') returning * into rd;
  insert into answers(round_id,player_id,answer_text,is_real) values(rd.id,null,q.correct_answer,true);
  update rooms set current_round=1,status='answering',updated_at=now() where id=r.id returning * into r;
  return jsonb_build_object('room',to_jsonb(r),'round',to_jsonb(rd));
end $$;

create or replace function public.leave_room(p_room_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.rooms; new_host uuid;
begin
  update players set connected=false where id=auth.uid() and room_id=p_room_id;
  select * into r from rooms where id=p_room_id;
  if r.host_player_id=auth.uid() then
    select id into new_host from players where room_id=p_room_id and connected order by joined_at limit 1;
    update rooms set host_player_id=new_host,updated_at=now() where id=p_room_id returning * into r;
  end if;
  return jsonb_build_object('room',to_jsonb(r));
end $$;

-- Realtime publication
alter publication supabase_realtime add table public.rooms;
alter publication supabase_realtime add table public.players;
alter publication supabase_realtime add table public.rounds;
alter publication supabase_realtime add table public.answers;
alter publication supabase_realtime add table public.votes;

-- Seed data
insert into public.questions(id,question,correct_answer,context) values
(1,'Which animal has fingerprints so similar to humans that they can sometimes be mistaken for them?','Koala','Koalas have fingerprints with loops and whorls remarkably similar to those of humans and some primates.'),
(2,'Which fruit is botanically classified as a berry, while a strawberry is not?','Banana','Botanically, a berry develops from a single flower with one ovary; bananas fit that definition.'),
(3,'Which country has the world’s northernmost capital city?','Iceland','Reykjavík is the northernmost national capital of a sovereign state.'),
(4,'What was the first food eaten in space by an American astronaut?','Applesauce','John Glenn ate applesauce from a squeeze tube during Friendship 7 in 1962.'),
(5,'Which animal can survive for a while after losing most of its brain because its vital functions are distributed unusually widely?','Cockroach','Cockroaches have decentralized nervous systems and can survive significant injury for a period, though they cannot live indefinitely without a head.'),
(6,'Which planet rotates so slowly that one rotation takes longer than its trip around the Sun?','Venus','Venus takes about 243 Earth days to rotate once, but about 225 Earth days to orbit the Sun.'),
(7,'Which common spice was once used as currency in parts of the ancient world?','Pepper','Black pepper was historically valuable enough to be traded like money and used in rents and taxes.'),
(8,'Which sea creature has three hearts?','Octopus','An octopus has two hearts that pump to the gills and one that pumps blood around the body.'),
(9,'Which metal is liquid at ordinary room temperature?','Mercury','Mercury remains liquid around typical indoor temperatures, unlike most metals.'),
(10,'Which country gave the Statue of Liberty to the United States?','France','France presented the statue as a gift commemorating the alliance between the two countries.'),
(11,'Which animal is known for producing cube-shaped droppings?','Wombat','Wombats form cube-shaped feces in their intestines, helping the droppings stay where they are placed.'),
(12,'What is the only mammal capable of true sustained flight?','Bat','Bats are the only mammals capable of powered, sustained flight; flying squirrels only glide.'),
(13,'Which ancient civilization developed a device often considered an early analog computer, the Antikythera mechanism?','Ancient Greek','The mechanism was made in the Hellenistic Greek world and used gears to model astronomical cycles.'),
(14,'Which country has more pyramids than Egypt?','Sudan','Sudan’s Nubian pyramids number in the hundreds and greatly outnumber Egypt’s surviving pyramids.'),
(15,'Which part of the human body has no blood vessels of its own and gets oxygen directly from surrounding fluid?','Cornea','The cornea is transparent and avascular; it receives oxygen largely from the air via the tear film.'),
(16,'Which bird can fly backward?','Hummingbird','Hummingbirds can generate lift on both the forward and backward strokes of their wings.'),
(17,'Which country is home to Longyearbyen, where traditional burial is difficult because of permafrost?','Norway','Longyearbyen is in Svalbard, where permafrost makes traditional burial problematic and bodies are generally not buried there.'),
(18,'Which element makes up most of the visible matter in the Sun?','Hydrogen','Hydrogen accounts for roughly three-quarters of the Sun’s mass and is the main fuel for its core fusion.'),
(19,'Which animal has an exceptionally long tongue that can exceed its body length?','Chameleon','Certain chameleons can project an extremely long tongue, sometimes exceeding their body length.'),
(20,'What kind of container was historically used to warm beds with hot water before modern rubber bottles?','Metal bed warmer','Early metal vessels filled with hot water or coals were used as bed warmers long before modern rubber hot-water bottles.'),
(21,'Which continent has no native ants?','Antarctica','Antarctica has no naturally established native ant populations because of its extreme climate.'),
(22,'Which animal can taste with its feet?','Butterfly','Butterflies have taste receptors on their feet, helping them identify suitable plants for laying eggs.'),
(23,'Which famous inventor was known to use short naps and a metal object to wake himself as he nodded off?','Thomas Edison','Edison reportedly used brief naps and held objects that dropped when he fell asleep to wake him.'),
(24,'Which country has a national flag that is not rectangular?','Nepal','Nepal’s flag consists of two stacked triangular pennants, making it the world’s only non-rectangular national flag.'),
(25,'Which animal has one of the largest hearts known in the animal kingdom?','Blue whale','A blue whale’s enormous heart is among the largest known hearts in the animal kingdom.'),
(26,'Which gas makes up the largest portion of Earth’s atmosphere?','Nitrogen','Earth’s atmosphere is about 78 percent nitrogen by volume.'),
(27,'Which ancient city was buried by the eruption of Mount Vesuvius in AD 79?','Pompeii','Pompeii was buried by volcanic material during the catastrophic eruption of Mount Vesuvius.'),
(28,'Which animal can project a tongue that is longer than its body?','Chameleon','Certain chameleons can project an extremely long tongue, sometimes exceeding their body length.'),
(29,'Which planet has the largest volcano in the Solar System?','Mars','Olympus Mons on Mars is the largest known volcano in the Solar System.'),
(30,'Which food can remain edible for an extraordinarily long time because it is low in water and naturally acidic?','Honey','Properly stored honey can remain stable for very long periods because of its low water activity and chemistry.')
on conflict (id) do update set question=excluded.question,correct_answer=excluded.correct_answer,context=excluded.context;

-- Ensure authenticated callers can use the functions.
grant execute on function public.create_room(text) to anon,authenticated;
grant execute on function public.join_room(text,text) to anon,authenticated;
grant execute on function public.reconnect_player(uuid) to anon,authenticated;
grant execute on function public.heartbeat(uuid) to anon,authenticated;
grant execute on function public.advance_inactive(uuid) to anon,authenticated;

grant execute on function public.start_game(uuid) to anon,authenticated;
grant execute on function public.submit_answer(uuid,text) to anon,authenticated;
grant execute on function public.submit_vote(uuid,uuid) to anon,authenticated;
grant execute on function public.get_round_view(uuid) to anon,authenticated;
grant execute on function public.finish_reveal(uuid) to anon,authenticated;
grant execute on function public.next_round(uuid) to anon,authenticated;
grant execute on function public.play_again(uuid) to anon,authenticated;
grant execute on function public.leave_room(uuid) to anon,authenticated;
