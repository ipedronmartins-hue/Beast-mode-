type Props={completed:boolean}

export default function ProgressBadge({completed}:Props){
 return <span>{completed?'✅ Concluído':'⏳ Pendente'}</span>
}
