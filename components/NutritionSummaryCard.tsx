import { NutritionStats } from '../types/nutritionStats'

export default function NutritionSummaryCard({stats}:{stats:NutritionStats}){
 return <div>{stats.calories} kcal • {stats.protein}g proteína</div>
}
