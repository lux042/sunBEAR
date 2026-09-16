using System.Windows.Forms;
namespace SunBear;
public sealed class SessionTree : TreeView
{
    readonly HashSet<TreeNode> selected=new();
    TreeNode? anchor;
    bool mouseSelecting;
    public event EventHandler? SelectionChanged;
    public IEnumerable<TreeNode> SelectedNodes=>selected.Where(n=>n.TreeView==this);
    public SessionTree(){DrawMode=TreeViewDrawMode.OwnerDrawText;}
    protected override void OnDrawNode(DrawTreeNodeEventArgs e){
        if(e.Node==null)return;
        bool active=selected.Contains(e.Node);
        using var brush=new SolidBrush(active?Color.FromArgb(218,236,224):BackColor);
        e.Graphics.FillRectangle(brush,e.Bounds);
        TextRenderer.DrawText(e.Graphics,e.Node.Text,Font,e.Bounds,active?Color.FromArgb(22,56,40):ForeColor,TextFormatFlags.VerticalCenter|TextFormatFlags.NoPrefix);
    }
    protected override void OnAfterSelect(TreeViewEventArgs e){base.OnAfterSelect(e);if(!mouseSelecting && e.Node!=null)Choose(e.Node,false,false);}
    protected override void WndProc(ref Message m){
        // Handle the native mouse message before TreeView changes its single selection.
        // OnMouseDown is too late: native AfterSelect can already have reset the anchor.
        if(m.Msg==0x0201){
            int packed=unchecked((int)m.LParam.ToInt64());
            var point=new Point((short)(packed&0xffff),(short)((packed>>16)&0xffff));
            var hit=HitTest(point);
            if(hit.Node!=null && (hit.Location&TreeViewHitTestLocations.PlusMinus)==0){
                var flags=m.WParam.ToInt64();
                mouseSelecting=true;try{Focus();SelectedNode=hit.Node;}finally{mouseSelecting=false;}
                Choose(hit.Node,(flags&0x0008)!=0,(flags&0x0004)!=0);
                m.Result=IntPtr.Zero;return;
            }
        }
        base.WndProc(ref m);
    }
    internal void ClickForTest(TreeNode node,bool control,bool shift){
        node.EnsureVisible();var bounds=node.Bounds;
        int x=bounds.Left+5,y=bounds.Top+bounds.Height/2;
        var m=Message.Create(Handle,0x0201,new IntPtr(1|(control?8:0)|(shift?4:0)),new IntPtr((y<<16)|(x&0xffff)));
        WndProc(ref m);
    }
    internal void Choose(TreeNode node,bool control,bool shift){
        selected.RemoveWhere(n=>n.TreeView!=this);
        if(shift && anchor?.TreeView==this){
            var visible=new List<TreeNode>();for(var n=Nodes.Count>0?Nodes[0]:null;n!=null;n=n.NextVisibleNode)visible.Add(n);
            int a=visible.IndexOf(anchor),b=visible.IndexOf(node);
            if(!control)selected.Clear();
            if(a>=0 && b>=0){foreach(var n in visible.Skip(Math.Min(a,b)).Take(Math.Abs(a-b)+1))if(n.Tag is Session)selected.Add(n);}
            else selected.Add(node);
        }else{if(!control)selected.Clear();if(control && selected.Contains(node))selected.Remove(node);else selected.Add(node);anchor=node;}
        Invalidate();SelectionChanged?.Invoke(this,EventArgs.Empty);
    }
}
