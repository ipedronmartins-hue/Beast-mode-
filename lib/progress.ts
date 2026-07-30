import type { Progress } from '../types/progress'

export const isWorkoutCompleted=(items:Progress[],workoutId:string)=>items.some(p=>p.workoutId===workoutId&&p.completed)

export const completedCount=(items:Progress[])=>items.filter(p=>p.completed).length
