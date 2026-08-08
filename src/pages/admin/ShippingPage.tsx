import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { AdminLayout } from '@/components/admin/AdminLayout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Truck, Package, ExternalLink } from 'lucide-react';
import { ShippingRatesPanel } from '@/components/admin/shipping/ShippingRatesPanel';
import { EmptyState } from '@/components/ui/empty-state';
import { usePlatformFormat } from '@/hooks/usePlatformFormat';

interface Carrier { id: string; code: string; name: string; tracking_url_template: string | null; is_active: boolean; }
interface Shipment { id: string; order_id: string; carrier_code: string | null; tracking_number: string | null; status: string; shipped_at: string | null; }


export default function ShippingPage() {
  const { data: carriers } = useQuery({
    queryKey: ['carriers'],
    queryFn: async () => {
      const { data, error } = await supabase.from('carriers' as any).select('*').order('code');
      if (error) throw error;
      return (data ?? []) as unknown as Carrier[];
    },
  });
  const { data: shipments } = useQuery({
    queryKey: ['shipments'],
    queryFn: async () => {
      const { data, error } = await supabase.from('shipments' as any).select('*').order('created_at', { ascending: false }).limit(50);
      if (error) throw error;
      return (data ?? []) as unknown as Shipment[];
    },
  });
  const { formatDateTime } = usePlatformFormat();

  const trackingUrl = (s: Shipment) => {
    if (!s.tracking_number || !s.carrier_code) return null;
    const tpl = carriers?.find((c) => c.code === s.carrier_code)?.tracking_url_template;
    if (!tpl) return null;
    return tpl.includes('{tracking_number}')
      ? tpl.replace('{tracking_number}', encodeURIComponent(s.tracking_number))
      : tpl.replace(/\{[^}]+\}/, encodeURIComponent(s.tracking_number));
  };


  return (
    <AdminLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold flex items-center gap-2">
            <Truck className="h-7 w-7" /> Shipping
          </h1>
          <p className="text-muted-foreground mt-1">Carriers and outbound parcels.</p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Carriers</CardTitle>
            <CardDescription>Built-in: PostNord, DHL, Bring. Add API credentials via secrets.</CardDescription>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow>
                <TableHead>Code</TableHead><TableHead>Name</TableHead><TableHead>Tracking template</TableHead><TableHead>Status</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {(carriers ?? []).map(c => (
                  <TableRow key={c.id}>
                    <TableCell className="font-mono text-sm">{c.code}</TableCell>
                    <TableCell className="font-medium">{c.name}</TableCell>
                    <TableCell className="text-xs text-muted-foreground truncate max-w-md">{c.tracking_url_template ?? '—'}</TableCell>
                    <TableCell>{c.is_active ? <Badge>Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <ShippingRatesPanel />


        <Card>
          <CardHeader>
            <CardTitle>Recent shipments</CardTitle>
            <CardDescription>Up to 50 most recent parcels across all orders.</CardDescription>
          </CardHeader>
          <CardContent>
            {(shipments?.length ?? 0) === 0 ? (
              <EmptyState
                icon={Package}
                title="No shipments yet"
                description="Once an order is fulfilled, its parcel and tracking will appear here."
                card={false}
                compact
              />
            ) : (
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Order</TableHead><TableHead>Carrier</TableHead><TableHead>Tracking</TableHead><TableHead>Status</TableHead><TableHead>Shipped</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {(shipments ?? []).map(s => {
                    const url = trackingUrl(s);
                    return (
                    <TableRow key={s.id}>
                      <TableCell>
                        <Button asChild variant="link" size="sm" className="h-auto p-0 font-mono text-xs">
                          <Link to={`/admin/orders?order=${s.order_id}`}>{s.order_id.slice(0, 8)}</Link>
                        </Button>
                      </TableCell>
                      <TableCell>{s.carrier_code ?? '—'}</TableCell>
                      <TableCell className="font-mono text-xs">
                        {s.tracking_number ? (
                          url ? (
                            <a
                              href={url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="inline-flex items-center gap-1 text-primary hover:underline"
                            >
                              {s.tracking_number}
                              <ExternalLink className="h-3 w-3" />
                            </a>
                          ) : (
                            s.tracking_number
                          )
                        ) : (
                          '—'
                        )}
                      </TableCell>
                      <TableCell><Badge variant="outline">{s.status}</Badge></TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {s.shipped_at ? formatDateTime(s.shipped_at) : '—'}
                      </TableCell>
                    </TableRow>
                    );
                  })}

                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
