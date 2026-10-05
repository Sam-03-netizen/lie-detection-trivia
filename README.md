# 🎭 Lie Detection Trivia

> A real-time multiplayer bluffing trivia game where everyone lies — and only one answer is actually true.

**Lie Detection Trivia** is a fast-paced multiplayer party game built around trivia, deception, and deduction.

Players join the same room using a short room code. Each round, everyone writes a believable fake answer to a strange trivia question. The real answer is secretly added to the pool, and players must figure out which answer is actually true.

Can you fool everyone else while spotting the truth?

---

## 🎮 Game Overview

Lie Detection Trivia supports **2+ players** playing together on separate devices.

Each game consists of **3 rounds**.

### The gameplay loop

```text
CREATE / JOIN ROOM
        ↓
     LOBBY
        ↓
    START GAME
        ↓
  QUESTION SHOWN
        ↓
 EVERYONE WRITES A BLUFF
        ↓
   ALL BLUFFS LOCKED
        ↓
     VOTING PHASE
        ↓
  FIND THE REAL ANSWER
        ↓
    REVEAL THE TRUTH
        ↓
   SCORE CALCULATION
        ↓
     LEADERBOARD
        ↓
     NEXT ROUND
        ↓
     ROUND 3
        ↓
   🏆 FINAL WINNER
```

---

## 🧠 How It Works

### 1. Create a Game

One player creates a game and receives a unique **4-character room code**.

Example:

```text
3481
```

The room code can be shared with other players.

---

### 2. Join the Game

Other players enter the room code from their own devices.

No account creation is required.

Each player joins anonymously using Supabase Anonymous Authentication.

---

### 3. Write a Bluff

A strange trivia question appears.

For example:

> Which ancient civilization developed the Antikythera mechanism?

Everyone writes a **believable fake answer**.

The goal is not to write something obviously ridiculous.

The best bluff should sound like it could actually be true.

---

### 4. Find the Truth

Once everyone has submitted their bluff, the game combines:

- Every player's fake answer
- The actual correct answer

Players then see all the answers and vote for the one they believe is real.

You **cannot vote for your own bluff**.

---

### 5. Reveal

Once everyone has voted, the game moves to the reveal phase.

The actual answer is revealed along with the explanation/context behind it.

---

### 6. Score Points

Players earn points in two ways.

#### 🎯 Find the Truth

Correctly identifying the real answer:

```text
+100 points
```

#### 🃏 Fool Other Players

If another player votes for your fake answer:

```text
+50 points
```

You can therefore score points even when you don't identify the truth — as long as your bluff is convincing.

---

### 7. Win the Game

The game contains **3 rounds**.

After the third round, the player with the highest total score wins.

🏆 **The best liar and detective takes the crown.**

---

# ✨ Features

## Multiplayer

- Real-time multiplayer
- Supports multiple players on separate devices
- Short room codes for joining
- Anonymous player sessions
- Real-time game state synchronization

## Game Mechanics

- 3-round game structure
- Curated trivia questions
- Player-generated bluff answers
- Hidden real answers
- Real-time voting
- No self-voting
- Automatic phase progression
- Server-authoritative scoring
- Round-by-round leaderboard
- Final winner screen
- Play Again functionality

## Reliability

The game is designed to handle:

- Players joining/leaving
- Player disconnects
- Reconnection
- Host leaving
- Host transfer
- Duplicate answer prevention
- Duplicate vote prevention
- Invalid votes
- Invalid answers
- Inactive players

---

# 🎨 Design

The interface uses a **retro arcade / pixel-inspired visual style**.

### Visual direction

- Bright electric blue
- Sunny yellow
- Cream/off-white surfaces
- Deep navy outlines
- Pixel-inspired borders
- Chunky arcade-style buttons
- Hard-edged shadows
- Responsive layouts
- Mobile-friendly controls

The goal is to make the game feel like a polished multiplayer party game rather than a traditional trivia application.

---

# 🛠️ Tech Stack

### Frontend

- **React**
- **TypeScript**
- **Vite**
- **Tailwind CSS**
- **Framer Motion**
- **Lucide React**

### Backend / Infrastructure

- **Supabase**
  - PostgreSQL
  - Realtime
  - Anonymous Authentication
  - Row Level Security
  - PostgreSQL RPC functions

### Deployment

- **Vercel**

---

# 🏗️ Architecture

The game uses a server-authoritative state machine.

```text
LOBBY
  │
  ▼
ANSWERING
  │
  ▼
VOTING
  │
  ▼
REVEAL
  │
  ▼
LEADERBOARD
  │
  ├──────────────┐
  │              │
  ▼              ▼
ANSWERING     FINISHED
  │
  ▼
NEXT ROUND
```

The server controls important game transitions and scoring rather than relying entirely on client-side state.

This prevents players from manipulating the game by modifying frontend state.

---

# 🗄️ Database

The Supabase database contains the following core tables:

```text
questions
    │
    └── Trivia question bank

rooms
    │
    └── Active game rooms

players
    │
    └── Players inside rooms

rounds
    │
    └── Individual rounds

answers
    │
    └── Player bluffs + hidden real answer

votes
    │
    └── Player votes
```

Important game operations are implemented as PostgreSQL RPC functions.

Examples include:

```text
create_room()
join_room()
start_game()
submit_answer()
submit_vote()
get_round_view()
finish_reveal()
next_round()
play_again()
leave_room()
heartbeat()
reconnect_player()
```

---

# 🔐 Security

The project uses Supabase Row Level Security and server-side RPC functions.

The true answer is intentionally hidden from players during the answering and voting phases.

The client does **not** receive the real answer until the reveal phase.

Players also cannot:

- Vote for their own bluff
- Submit multiple answers
- Submit multiple votes
- Manually advance important game phases
- Directly modify their score

---

# 📁 Project Structure

```text
lie-detection-trivia/
│
├── src/
│   ├── main.tsx
│   ├── styles.css
│   ├── supabase.ts
│   ├── types.ts
│   └── questions.ts
│
├── supabase.sql
├── index.html
├── package.json
├── package-lock.json
├── tsconfig.json
├── vite.config.ts
├── .env.example
├── .gitignore
└── README.md
```

---

# 🚀 Getting Started

## Prerequisites

Make sure you have:

- Node.js installed
- A Supabase project
- Git
- A modern web browser

---

## 1. Clone the Repository

```bash
git clone <YOUR_REPOSITORY_URL>
cd lie-detection-trivia
```

---

## 2. Install Dependencies

```bash
npm install
```

---

## 3. Create a Supabase Project

Create a new project in Supabase.

Then open:

```text
Authentication
    ↓
Providers
    ↓
Anonymous Sign-ins
```

Enable **Anonymous Sign-ins** and save the configuration.

---

## 4. Set Up the Database

Open the Supabase SQL Editor.

Copy the contents of:

```text
supabase.sql
```

Paste it into the SQL Editor and execute it.

This creates:

- Database tables
- RLS policies
- RPC functions
- Realtime configuration
- Trivia questions

---

## 5. Configure Environment Variables

Create a `.env` file in the project root.

```env
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_ANON_KEY=your_supabase_public_key
```

For example:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-public-key
```

### ⚠️ Important

Never put your Supabase:

```text
service_role
secret key
```

inside the frontend application.

Only use the public client key.

Also make sure `.env` is included in `.gitignore`.

---

# 💻 Run Locally

Start the development server:

```bash
npm run dev
```

Vite will provide a local URL, usually:

```text
http://localhost:5173
```

Open it in your browser.

---

# 🏗️ Production Build

Before deploying, test the production build locally:

```bash
npm run build
```

If successful, preview it with:

```bash
npm run preview
```

---

# ☁️ Deploying to Vercel

The project is designed to be deployed using Vercel.

### 1. Push the project to GitHub

```bash
git add .
git commit -m "Finalize Lie Detection Trivia"
git push origin main
```

### 2. Import the repository into Vercel

Create a new Vercel project and select the GitHub repository.

Vercel should automatically detect:

```text
Framework: Vite
Build Command: npm run build
Output Directory: dist
```

### 3. Add Environment Variables

In Vercel project settings, add:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

Use the same public Supabase values used locally.

### 4. Deploy

Deploy the project.

After deployment, the game will be available through a public URL.

---

# 🧪 Testing Checklist

Before considering the game ready for release, test the complete multiplayer flow.

### Lobby

- [ ] Create a room
- [ ] Room code appears
- [ ] Second device joins
- [ ] Third device joins
- [ ] All players appear in lobby
- [ ] Host can start the game

### Round

- [ ] Question appears
- [ ] Real answer is hidden
- [ ] Every player submits one bluff
- [ ] Duplicate answers are prevented
- [ ] Voting starts only after everyone submits

### Voting

- [ ] All answers are visible
- [ ] Real answer is mixed with bluffs
- [ ] Players cannot vote for themselves
- [ ] Each player can vote independently
- [ ] Voting ends only after everyone votes

### Reveal

- [ ] Real answer is revealed
- [ ] Explanation appears
- [ ] Correct voters receive +100
- [ ] Bluffers receive +50 per fooled player
- [ ] Leaderboard updates correctly

### Multiple Rounds

- [ ] Round 2 starts correctly
- [ ] Round 3 starts correctly
- [ ] Scores carry across rounds
- [ ] Final winner is calculated correctly

### Multiplayer Reliability

- [ ] Player disconnects
- [ ] Player reconnects
- [ ] Host leaves
- [ ] Host transfers correctly
- [ ] Game does not get stuck

### Production

- [ ] Test on desktop
- [ ] Test on mobile
- [ ] Test on multiple networks
- [ ] Verify Supabase environment variables
- [ ] Verify production build
- [ ] Verify public Vercel URL

---

# 🎯 Game Rules

| Action | Points |
|---|---:|
| Correctly identify the real answer | +100 |
| Another player chooses your bluff | +50 |
| Vote for your own answer | Not allowed |
| Submit multiple answers | Not allowed |
| Submit multiple votes | Not allowed |

The final winner is the player with the highest score after **3 rounds**.

---

# 🔄 Replaying

After the final round, players can choose:

```text
PLAY AGAIN
```

The existing room can be reused for another game.

Scores and rounds are reset for the new game.

---

# 📱 Responsive Design

Lie Detection Trivia is designed to work across:

- 💻 Desktop
- 💻 Laptop
- 📱 Mobile
- 📱 Tablet

The core multiplayer experience remains usable regardless of screen size.

---

# 🧩 Future Ideas

The current version intentionally focuses on the core gameplay loop.

Potential future additions could include:

- Custom question packs
- Categories
- Difficulty levels
- More game modes
- Timed rounds
- Player statistics
- Sound effects
- Music
- Achievements
- Spectator mode
- Larger multiplayer rooms

These are intentionally outside the current MVP scope.

---

# 🏆 Why This Project?

Lie Detection Trivia combines several practical software engineering concepts:

- Real-time multiplayer systems
- Client/server architecture
- PostgreSQL database design
- Supabase Realtime
- Authentication
- Row Level Security
- Server-side game logic
- State machines
- Concurrent user interactions
- Responsive frontend development
- Production deployment

The project demonstrates how a relatively simple game mechanic can be turned into a complete real-time web application.

---

# 📜 License

This project is currently intended as a personal/project submission.

Add your preferred license here if the project is later released as open source.

---

## 👩‍💻 Built With

**React + TypeScript + Vite + Supabase + Framer Motion**

Built as a real-time multiplayer bluffing and deduction game.
