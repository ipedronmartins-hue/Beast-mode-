import type { Achievement } from '../types/achievement'

export default function AchievementCard({achievement}:{achievement:Achievement}){
 return <div>{achievement.icon} {achievement.title}</div>
}
