# Lie-Detection Trivia

A 3-round realtime social bluffing/trivia game built with React + Vite + Supabase.

## Local setup

1. Create a Supabase project.
2. Enable **Anonymous Sign-ins** in Authentication > Providers.
3. Run `supabase.sql` in the Supabase SQL Editor.
4. Copy `.env.example` to `.env` and fill in:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. Install dependencies with `npm install`.
6. Run `npm run dev`.

## Production

Build with `npm run build` and deploy the Vite `dist/` directory to a static host such as Vercel. The Supabase project provides PostgreSQL, anonymous sessions, RPCs and Realtime.

## Game rules

- 3 rounds.
- Every round has one factual answer and one believable fake answer from each player.
- Correct truth vote: +100.
- Each player fooled by your fake answer: +50.
- You cannot vote for your own bluff.
- Highest total after round 3 wins.
