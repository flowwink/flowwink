import { useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { logger } from '@/lib/logger';
import { Loader2, Upload } from 'lucide-react';

interface VideoUploadButtonProps {
  /** Called with the public URL of the uploaded video. */
  onUploaded: (url: string) => void;
  folder?: string;
  title?: string;
}

const MAX_BYTES = 50 * 1024 * 1024; // 50 MB — keep hero backgrounds light

/**
 * Uploads an MP4/WebM to the cms-images bucket and returns its public URL.
 * Videos are stored as-is (no transcoding in the browser).
 */
export function VideoUploadButton({ onUploaded, folder = 'pages', title = 'Upload a video (MP4/WebM)' }: VideoUploadButtonProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isUploading, setIsUploading] = useState(false);
  const { toast } = useToast();

  const handleFile = async (file: File) => {
    if (!file.type.startsWith('video/')) {
      toast({ title: 'Not a video', description: 'Please pick an MP4 or WebM file.', variant: 'destructive' });
      return;
    }
    if (file.size > MAX_BYTES) {
      toast({
        title: 'File too large',
        description: 'Keep background videos under 50 MB for fast page loads.',
        variant: 'destructive',
      });
      return;
    }

    setIsUploading(true);
    try {
      const ext = file.name.match(/\.[^/.]+$/)?.[0] || '.mp4';
      const baseName = file.name.replace(/\.[^/.]+$/, '').replace(/[^a-zA-Z0-9-_]/g, '-');
      const path = `${folder}/${Date.now()}-${baseName}${ext}`;

      const { error } = await supabase.storage
        .from('cms-images')
        .upload(path, file, { contentType: file.type, cacheControl: '31536000' });

      if (error) throw error;

      const { data } = supabase.storage.from('cms-images').getPublicUrl(path);
      onUploaded(data.publicUrl);
      toast({ title: 'Video uploaded', description: 'The video is now available in your media library.' });
    } catch (error) {
      logger.error('Video upload failed', error);
      toast({ title: 'Upload failed', description: 'Could not upload the video. Please try again.', variant: 'destructive' });
    } finally {
      setIsUploading(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  };

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        accept="video/mp4,video/webm,video/quicktime"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleFile(file);
        }}
      />
      <Button
        type="button"
        variant="outline"
        size="icon"
        title={title}
        disabled={isUploading}
        onClick={() => inputRef.current?.click()}
      >
        {isUploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
      </Button>
    </>
  );
}
