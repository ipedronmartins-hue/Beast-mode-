type Props={label:string,value:string|number}

export default function WorkoutStatsCard({label,value}:Props){
 return <div><strong>{value}</strong><p>{label}</p></div>
}
