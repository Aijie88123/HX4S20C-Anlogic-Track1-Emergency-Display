param([string]$Port,[string]$Text,[switch]$Clear,[switch]$RenderOnly,[string]$OutputPrefix)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Text;
using System.Drawing.Drawing2D;
public sealed class CaptionImage {
 public int Width; public byte[] Data; public Bitmap Preview; public string Font;
}
public static class SubtitleCodec {
 public static ushort Crc(byte[] data,int count) {
  int c=65535;for(int i=0;i<count;i++){c^=data[i]<<8;for(int k=0;k<8;k++)c=((c&32768)!=0?((c<<1)^0x1021):(c<<1))&65535;}return (ushort)c;
 }
 public static byte[] Packet(byte op,byte id,int index,ushort digest,byte[] data) {
  byte[] p=new byte[28];p[0]=18;p[1]=1;p[2]=op;p[3]=id;p[4]=(byte)index;p[5]=(byte)(index>>8);p[6]=(byte)digest;p[7]=(byte)(digest>>8);
  if(data!=null)Array.Copy(data,0,p,8,16);p[24]=0x31;p[25]=0x42;p[26]=0x55;p[27]=0x53;return p;
 }
 public static byte[] Frame(byte[] p) {
  byte[] f=new byte[33];f[0]=27;f[1]=83;f[2]=1;Array.Copy(p,0,f,3,28);ushort c=Crc(p,28);f[31]=(byte)c;f[32]=(byte)(c>>8);return f;
 }
 public static void CheckReply(byte[] r,byte[] p) {
  if(r.Length!=10||r[0]!=27||r[1]!=65||r[2]!=1||r[3]!=p[3]||r[4]!=p[2]||r[5]!=p[4]||r[6]!=p[5]||Crc(r,8)!=(r[8]|r[9]<<8))throw new Exception("Invalid subtitle reply. Check matching A/B firmware and exclusive COM access.");
  if(r[7]!=0)throw new Exception("Subtitle rejected, status="+r[7]+". Please visually verify the last committed subtitle. 2=UART CRC,3=offline,4=busy,5=network timeout,6=format,10=width,11=order,13=digest.");
 }
 public static CaptionImage Raster(string text) {
  if(String.IsNullOrWhiteSpace(text))throw new Exception("Please enter a non-empty single-line message, or use Clear.");
  if(text.IndexOf('\r')>=0||text.IndexOf('\n')>=0)throw new Exception("Only one line is supported.");
  if(text.Length>256)throw new Exception("Message too long.");
  for(int size=16;size>=10;size--)using(Font font=new Font("Microsoft YaHei",size,FontStyle.Regular,GraphicsUnit.Pixel))using(Bitmap temp=new Bitmap(1400,64)) {
   using(Graphics g=Graphics.FromImage(temp)) {
    g.Clear(Color.Black);g.TextRenderingHint=TextRenderingHint.SingleBitPerPixelGridFit;g.SmoothingMode=SmoothingMode.None;
    if(g.MeasureString(text,font,1400,StringFormat.GenericTypographic).Width>1100)throw new Exception("Message too wide. Maximum 1024 font pixels, roughly 64 Chinese characters.");
    g.DrawString(text,font,Brushes.White,new PointF(0,0),StringFormat.GenericTypographic);
   }
   int left=1400,right=-1,top=64,bottom=-1;
   for(int y=0;y<64;y++)for(int x=0;x<1400;x++)if(temp.GetPixel(x,y).R>127){left=Math.Min(left,x);right=Math.Max(right,x);top=Math.Min(top,y);bottom=Math.Max(bottom,y);}
   if(right<left)throw new Exception("The selected font produced no visible glyphs.");
   if(bottom-top+1>16)continue;
   int width=((right-left+1+15)/16)*16;if(width>1024)throw new Exception("Message too wide. Maximum 1024 font pixels; shorten it.");
   byte[] data=new byte[2048];Bitmap preview=new Bitmap(width*2,32);int offset=(16-(bottom-top+1))/2;
   using(Graphics g=Graphics.FromImage(preview))g.Clear(Color.FromArgb(0x12,0x38,0x5a));
   for(int y=0;y<16;y++)for(int x=0;x<1024;x++) {
    int sy=y-offset+top;bool on=x<=right-left&&sy>=top&&sy<=bottom&&temp.GetPixel(x+left,sy).R>127;
    if(on){int word=y*64+x/16;int bit=15-x%16;data[word*2+bit/8]|=(byte)(1<<(bit%8));if(x<width)for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++)preview.SetPixel(x*2+xx,y*2+yy,Color.White);}
   }
   return new CaptionImage{Width=width,Data=data,Preview=preview,Font=font.FontFamily.Name+" "+size+"px"};
  }
  throw new Exception("Could not fit font height into16 pixels.");
 }
}
"@
function Open-CaptionPort([string]$Name) {
 $s=[System.IO.Ports.SerialPort]::new($Name,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
 $s.Handshake=[System.IO.Ports.Handshake]::None;$s.DtrEnable=$false;$s.RtsEnable=$false;$s.ReadTimeout=3000;$s.WriteTimeout=3000
 $s.NewLine="`n";$s.Encoding=[Text.Encoding]::ASCII
 try{$s.Open();$s.DiscardInBuffer();return $s}catch{$s.Dispose();throw}
}
function Send-CaptionPacket($Serial,[byte[]]$Packet) {
 [byte[]]$frame=[SubtitleCodec]::Frame($Packet);$Serial.Write($frame,0,$frame.Length)
 [byte[]]$reply=New-Object byte[] 10;$n=0
 while($n -lt 10){$got=$Serial.Read($reply,$n,10-$n);if($got -le 0){throw 'Incomplete reply.'};$n+=$got}
 [SubtitleCodec]::CheckReply($reply,$Packet)
}
function Send-Caption([string]$Name,$Image,[bool]$IsClear,[scriptblock]$Progress) {
 $s=Open-CaptionPort $Name
 try {
  [byte]$id=Get-Random -Minimum 1 -Maximum 256
  if($IsClear){Send-CaptionPacket $s ([SubtitleCodec]::Packet(3,$id,0,0,$null));return}
  [uint16]$digest=[SubtitleCodec]::Crc($Image.Data,2048)
  Send-CaptionPacket $s ([SubtitleCodec]::Packet(0,$id,$Image.Width,0,$null))
  for($i=0;$i -lt 128;$i++){
   [byte[]]$block=New-Object byte[] 16;[Array]::Copy($Image.Data,$i*16,$block,0,16)
   Send-CaptionPacket $s ([SubtitleCodec]::Packet(1,$id,$i,0,$block))
   if($Progress){& $Progress ($i+1)}
  }
  Send-CaptionPacket $s ([SubtitleCodec]::Packet(2,$id,128,$digest,$null))
 } finally {if($s.IsOpen){$s.Close()};$s.Dispose()}
}
if($RenderOnly){
 if(!$OutputPrefix){throw 'RenderOnly requires OutputPrefix.'}
 $im=[SubtitleCodec]::Raster($Text)
 try{
  $prefix=[IO.Path]::GetFullPath($OutputPrefix);[IO.File]::WriteAllBytes($prefix+'.bin',$im.Data);$im.Preview.Save($prefix+'.png',[Drawing.Imaging.ImageFormat]::Png)
  $frames=[Collections.Generic.List[byte]]::new();[uint16]$digest=[SubtitleCodec]::Crc($im.Data,2048)
  $frames.AddRange([SubtitleCodec]::Frame([SubtitleCodec]::Packet(0,42,$im.Width,0,$null)))
  for($i=0;$i -lt 128;$i++){[byte[]]$block=New-Object byte[] 16;[Array]::Copy($im.Data,$i*16,$block,0,16);$frames.AddRange([SubtitleCodec]::Frame([SubtitleCodec]::Packet(1,42,$i,0,$block)))}
  $frames.AddRange([SubtitleCodec]::Frame([SubtitleCodec]::Packet(2,42,128,$digest,$null)))
  [IO.File]::WriteAllBytes($prefix+'.uart',$frames.ToArray())
  @{text=$Text;width=$im.Width;height=16;scale=2;font=$im.Font;crc16=[int]$digest;blocks=128} | ConvertTo-Json | Set-Content ($prefix+'.json') -Encoding UTF8
 }finally{$im.Preview.Dispose()};return
}
if($Port){
 if($Clear){Send-Caption $Port $null $true $null;Write-Output 'Subtitle cleared at frame boundary.'}
 else{$im=[SubtitleCodec]::Raster($Text);try{Send-Caption $Port $im $false $null;Write-Output 'Subtitle committed at frame boundary.'}finally{$im.Preview.Dispose()}};return
}
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new();$form.Text='FPGA 中英文滚动字幕';$form.Size=[Drawing.Size]::new(780,400);$form.StartPosition='CenterScreen'
$label=[Windows.Forms.Label]::new();$label.Text='B板 CH340 串口：';$label.Location=[Drawing.Point]::new(20,22);$label.AutoSize=$true;$form.Controls.Add($label)
$ports=[Windows.Forms.ComboBox]::new();$ports.Location=[Drawing.Point]::new(160,18);$ports.Width=150;$ports.DropDownStyle='DropDownList';$form.Controls.Add($ports)
$refresh=[Windows.Forms.Button]::new();$refresh.Text='刷新端口';$refresh.Location=[Drawing.Point]::new(330,16);$refresh.Width=100;$form.Controls.Add($refresh)
$info=[Windows.Forms.Label]::new();$info.Text='输入字幕正文即可；115200 / 8N1。原串口助手需先关闭。';$info.Location=[Drawing.Point]::new(20,62);$info.AutoSize=$true;$form.Controls.Add($info)
$input=[Windows.Forms.TextBox]::new();$input.Location=[Drawing.Point]::new(20,92);$input.Width=720;$input.MaxLength=256;$input.Font=[Drawing.Font]::new('Microsoft YaHei',12);$input.Text='紧急通知：请按绿色路线有序疏散 EXIT A';$form.Controls.Add($input)
$preview=[Windows.Forms.Button]::new();$preview.Text='预览';$preview.Location=[Drawing.Point]::new(20,140);$form.Controls.Add($preview)
$send=[Windows.Forms.Button]::new();$send.Text='发送字幕';$send.Location=[Drawing.Point]::new(120,140);$send.Width=110;$form.Controls.Add($send)
$clearButton=[Windows.Forms.Button]::new();$clearButton.Text='清除自定义字幕';$clearButton.Location=[Drawing.Point]::new(250,140);$clearButton.Width=150;$form.Controls.Add($clearButton)
$panel=[Windows.Forms.Panel]::new();$panel.Location=[Drawing.Point]::new(20,190);$panel.Size=[Drawing.Size]::new(720,65);$panel.AutoScroll=$true;$panel.BackColor=[Drawing.Color]::FromArgb(0x12,0x38,0x5a);$form.Controls.Add($panel)
$picture=[Windows.Forms.PictureBox]::new();$picture.SizeMode='AutoSize';$panel.Controls.Add($picture)
$progress=[Windows.Forms.ProgressBar]::new();$progress.Location=[Drawing.Point]::new(20,275);$progress.Width=720;$progress.Maximum=128;$form.Controls.Add($progress)
$status=[Windows.Forms.Label]::new();$status.Location=[Drawing.Point]::new(20,312);$status.Size=[Drawing.Size]::new(720,40);$status.Text='等待发送。新字幕完整接收后切换；应急时显示在地图状态栏上方。';$form.Controls.Add($status)
$refresh.Add_Click({$ports.Items.Clear();foreach($p in [IO.Ports.SerialPort]::GetPortNames()|Sort-Object){[void]$ports.Items.Add($p)};if($ports.Items.Count){$ports.SelectedIndex=0}})
$preview.Add_Click({try{$im=[SubtitleCodec]::Raster($input.Text);if($picture.Image){$picture.Image.Dispose()};$picture.Image=$im.Preview;$status.Text="预览：$($im.Width)×16 字模，显示放大2倍。"}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'预览失败')}})
$send.Add_Click({
 $im=$null
 try{
  if(!$ports.SelectedItem){throw '请选择B板CH340串口。'}
  $send.Enabled=$false;$clearButton.Enabled=$false;$refresh.Enabled=$false;$preview.Enabled=$false
  $im=[SubtitleCodec]::Raster($input.Text);if($picture.Image){$picture.Image.Dispose()};$picture.Image=$im.Preview
  $progress.Value=0;$status.Text='发送中，旧字幕保持显示……';[Windows.Forms.Application]::DoEvents()
  Send-Caption ([string]$ports.SelectedItem) $im $false {$progress.Value=$args[0];[Windows.Forms.Application]::DoEvents()}
  $status.Text='字幕已在A板帧边界提交；正常画面底部或应急地图状态栏上方滚动。'
 }catch{$status.Text='通信未完成，请目视确认显示结果；未完整提交的数据不会替换旧字幕。';[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'发送失败')}
 finally{$send.Enabled=$true;$clearButton.Enabled=$true;$refresh.Enabled=$true;$preview.Enabled=$true}
})
$clearButton.Add_Click({try{if(!$ports.SelectedItem){throw '请选择串口。'};$send.Enabled=$false;$clearButton.Enabled=$false;Send-Caption ([string]$ports.SelectedItem) $null $true $null;$progress.Value=0;$status.Text='已清除，恢复原字幕/地图界面。'}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'清除失败')}finally{$send.Enabled=$true;$clearButton.Enabled=$true}})
$form.Add_FormClosed({if($picture.Image){$picture.Image.Dispose()}})
$refresh.PerformClick();$preview.PerformClick();[void]$form.ShowDialog()
