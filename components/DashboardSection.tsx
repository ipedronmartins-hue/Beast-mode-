import { ReactNode } from 'react'

type Props={title:string,children:ReactNode}

export default function DashboardSection({title,children}:Props){
 return <section><h2>{title}</h2>{children}</section>
}
