import WorkoutCard from './WorkoutCard'
import type { Workout } from '../types/workout'

export default function WorkoutList({workouts}:{workouts:Workout[]}){
 return (<div>{workouts.map(w=><WorkoutCard key={w.id} workout={w} />)}</div>)
}
