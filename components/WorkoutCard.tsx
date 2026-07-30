import type { Workout } from '../types/workout'

export default function WorkoutCard({workout}:{workout:Workout}){
 return (<div><h3>{workout.title}</h3><p>{workout.duration} min</p><p>{workout.difficulty}</p><p>{workout.completed?'Completed':'Pending'}</p></div>)
}
