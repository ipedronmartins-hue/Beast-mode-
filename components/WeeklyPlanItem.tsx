type Props={day:string,focus:string}

export default function WeeklyPlanItem({day,focus}:Props){
 return <div><strong>{day}</strong><span>{focus}</span></div>
}
