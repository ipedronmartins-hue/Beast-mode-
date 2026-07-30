type Props={onClick?:()=>void}
export default function AIWorkoutButton({onClick}:Props){
 return <button onClick={onClick}>🤖 Gerar treino com IA</button>
}
