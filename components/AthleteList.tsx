import { mockAthletes } from '../lib/mockAthletes'

export default function AthleteList(){
 return (<ul>{mockAthletes.map(a=><li key={a.id}>{a.name} - {a.sport}</li>)}</ul>)
}
