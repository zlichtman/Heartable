import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'A mixtape for you · Heartable',
  description: 'Songs, notes, and photographs, shared with you on Heartable.',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
  icons: { icon: '/heartable.png' },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        {children}
      </body>
    </html>
  );
}
