import type { Workout } from '../types/workout'

export function totalWorkoutMinutes(workouts: Workout[]){
 return workouts.reduce((t,w)=>t+w.duration,0)
}
