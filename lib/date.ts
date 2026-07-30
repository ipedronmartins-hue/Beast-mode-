export function formatWorkoutDate(date:Date|string){
 const d=typeof date==='string'?new Date(date):date
 return d.toLocaleDateString('pt-PT',{day:'2-digit',month:'2-digit',year:'numeric'})
}
