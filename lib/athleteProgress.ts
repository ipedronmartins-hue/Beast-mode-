import { mockProgress } from './mockProgress'

export function getAthleteProgress(athleteId:string){
 return mockProgress.filter(p=>p.athleteId===athleteId)
}
