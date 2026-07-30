import AchievementCard from './AchievementCard'
import { mockAchievements } from '../lib/mockAchievements'

export default function AchievementsList(){
 return <div>{mockAchievements.map(a=><AchievementCard key={a.id} achievement={a} />)}</div>
}
