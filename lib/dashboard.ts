import { mockAthletes } from './mockAthletes'
import { mockWorkouts } from './mockWorkouts'

export const dashboardStats={
 totalAthletes:mockAthletes.length,
 totalWorkouts:mockWorkouts.length,
 completedWorkouts:mockWorkouts.filter(w=>w.completed).length,
 activeAthletes:mockAthletes.filter(a=>a.active).length
}
