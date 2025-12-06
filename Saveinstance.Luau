local a=1;local b=true;local c=false;local d=[==[]==]local e=""local f=800000;local g=0;local h=true;local i=false;local
j=false;local k=false;local l=true;local m=true;if game.CoreGui:FindFirstChild("NFLib")then
game.CoreGui:FindFirstChild("NFLib"):Destroy()end;local n={}local
o=Instance.new("ScreenGui")o.Name="NFLib"o.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;o.Parent=game.CoreGui;local
p=Instance.new("ScrollingFrame")p.Name="Container"p.Parent=o;p.Active=false;p.BackgroundColor3=Color3.fromRGB(255,255,255)p.BackgroundTransparency=1.000;p.BorderSizePixel=0;p.Position=UDim2.new(0.864545425,0,0.67027743,0)p.Size=UDim2.new(0,209,0,259)p.BottomImage=""p.CanvasSize=UDim2.new(0,0,0,0)p.MidImage=""p.ScrollingEnabled=false;p.TopImage=""local
q=Instance.new("UIListLayout")q.Parent=p;q.HorizontalAlignment=Enum.HorizontalAlignment.Center;q.SortOrder=Enum.SortOrder.LayoutOrder;q.VerticalAlignment=Enum.VerticalAlignment.Bottom;q.Padding=UDim.new(0,5)function
tick(r,s)if r.Parent then r:FindFirstChild("Line"):TweenSize(UDim2.new(0,197,0,1),"Out","Linear",s)end;wait(s)if
r.Parent then r.Parent:TweenSize(UDim2.new(0,197,0,0),"Out","Quint",1.5)wait(1)r.Parent:Destroy()end end;function
n:Notification(t,u,v,w)if t==nil then t="Preview"end;if u==nil then u="This is an example of a notification using
NFLib"end;if v==nil then v=5 end;if w==nil then w=Color3.fromRGB(20,169,255)end;local
x=Instance.new("Frame")x.Name="WindowHolder"x.Parent=p;x.BackgroundColor3=Color3.fromRGB(33,33,33)x.BackgroundTransparency=1.000;x.ClipsDescendants=true;x.Position=UDim2.new(0.839661181,0,0.796762526,0)x.Size=UDim2.new(0,197,0,74)local
y=Instance.new("Frame")y.Name="Window"y.Parent=x;y.BackgroundColor3=Color3.fromRGB(33,33,33)y.ClipsDescendants=true;y.Size=UDim2.new(0,197,0,74)local
z=Instance.new("Frame")z.Name="Main"z.Parent=y;z.BackgroundColor3=Color3.fromRGB(255,255,255)z.BackgroundTransparency=1.000;z.Size=UDim2.new(0,197,0,57)local
A=Instance.new("UICorner")A.CornerRadius=UDim.new(0,3)A.Parent=y;local
B=Instance.new("Frame")B.Name="Line"B.Parent=y;B.BackgroundColor3=w;B.BorderSizePixel=0;B.ClipsDescendants=true;B.Position=UDim2.new(0,0,0.987179399,0)B.Size=UDim2.new(0,0,0,1)local
C=Instance.new("TextLabel")C.Name="Title"C.Parent=z;C.BackgroundColor3=Color3.fromRGB(255,255,255)C.BackgroundTransparency=1.000;C.ClipsDescendants=true;C.Size=UDim2.new(0,197,0,27)C.Font=Enum.Font.GothamBold;C.Text=t;C.TextColor3=Color3.fromRGB(231,231,231)C.TextSize=14.000;local
D=Instance.new("TextLabel")D.Name="Text"D.Parent=z;D.BackgroundColor3=Color3.fromRGB(255,255,255)D.BackgroundTransparency=1.000;D.ClipsDescendants=true;D.Position=UDim2.new(0,0,0,26)D.Font=Enum.Font.GothamSemibold;D.Text=u;D.TextColor3=Color3.fromRGB(231,231,231)D.TextSize=13.000;D.TextWrapped=true;D.TextYAlignment=Enum.TextYAlignment.Top
