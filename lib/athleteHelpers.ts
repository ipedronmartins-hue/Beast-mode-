import { mockWorkouts } from './mockWorkouts'

export function getWorkoutsByAthlete(athleteId:string){
 return mockWorkouts.filter(w=>w.athleteId===athleteId)
}

export function getCompletionRate(athleteId:string){
 const workouts=getWorkoutsByAthlete(athleteId)
 if(workouts.length===0) return 0
 return Math.round((workouts.filter(w=>w.completed).length/workouts.length)*100)
}
