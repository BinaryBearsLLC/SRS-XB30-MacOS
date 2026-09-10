import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {title:'XB30 Controller · Your speaker, one touch closer',description:'Explore the BinaryBears XB30 in 3D. Shape its sound and lighting, then control your speaker from the Mac menu bar.',icons:{icon:'/favicon.svg'}};
export default function RootLayout({children}:Readonly<{children:React.ReactNode}>) {return <html lang="en"><body>{children}</body></html>}
