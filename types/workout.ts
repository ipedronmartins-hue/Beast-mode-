export interface Workout {
 id:string;
 athleteId:string;
 title:string;
 duration:number;
 difficulty:'easy'|'medium'|'hard';
 completed:boolean;
}
