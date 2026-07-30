import type { Progress } from '../types/progress'

export function completedStreak(items: Progress[]){
 let streak=0
 for(const item of items){
  if(item.completed) streak++
 }
 return streak
}
