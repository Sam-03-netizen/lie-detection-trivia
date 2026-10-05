export type RoomStatus = 'lobby'|'answering'|'voting'|'reveal'|'leaderboard'|'finished';
export interface Room { id:string; code:string; host_player_id:string; status:RoomStatus; current_round:number; updated_at:string; }
export interface Player { id:string; room_id:string; name:string; score:number; connected:boolean; joined_at:string; }
export interface Round { id:string; room_id:string; round_number:number; question_id:number; status:RoomStatus; }
export interface Question { id:number; question:string; correct_answer:string; context:string; }
export interface Answer {
  id: string;
  round_id: string;
  player_id?: string | null;
  answer_text: string;
  is_real?: boolean;
  is_mine?: boolean;
}export interface Vote { id:string; round_id:string; player_id:string; answer_id:string; }
export interface RoundScore { player_id:string; name:string; score_delta:number; total_score:number; truth_found:boolean; fooled:number; }
