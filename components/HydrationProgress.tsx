type Props={liters:number,target:number}

export default function HydrationProgress({liters,target}:Props){
 return <div>{liters}L / {target}L</div>
}
