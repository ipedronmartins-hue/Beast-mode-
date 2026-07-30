type Props={minutes:number;completed:number}

export default function WorkoutSummary({minutes,completed}:Props){
 return <div><p>Total: {minutes} min</p><p>Concluídos: {completed}</p></div>
}
